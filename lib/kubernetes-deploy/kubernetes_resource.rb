require 'json'
require 'open3'
require 'shellwords'
require 'kubernetes-deploy/kubectl'

module KubernetesDeploy
  class KubernetesResource
    attr_reader :name, :namespace, :file, :context
    attr_writer :type, :deploy_started

    TIMEOUT = 5.minutes

    def self.for_type(type:, name:, namespace:, context:, file:, logger:)
      subclass = case type
      when 'cloudsql' then Cloudsql
      when 'configmap' then ConfigMap
      when 'deployment' then Deployment
      when 'pod' then Pod
      when 'redis' then Redis
      when 'bugsnag' then Bugsnag
      when 'ingress' then Ingress
      when 'persistentvolumeclaim' then PersistentVolumeClaim
      when 'service' then Service
      when 'podtemplate' then PodTemplate
      when 'poddisruptionbudget' then PodDisruptionBudget
      end

      if subclass
        subclass.new(name: name, namespace: namespace, context: context, file: file, logger: logger)
      else
        inst = new(name: name, namespace: namespace, context: context, file: file, logger: logger)
        inst.tap { |r| r.type = type }
      end
    end

    def self.timeout
      self::TIMEOUT
    end

    def timeout
      self.class.timeout
    end

    def initialize(name:, namespace:, context:, file:, logger:)
      # subclasses must also set these if they define their own initializer
      @name = name
      @namespace = namespace
      @context = context
      @file = file
      @logger = logger
    end

    def id
      "#{type}/#{name}"
    end

    def sync
      log_status
    end

    def deploy_failed?
      false
    end

    def deploy_succeeded?
      if @deploy_started && !@success_assumption_warning_shown
        @logger.warn("Don't know how to monitor resources of type #{type}. Assuming #{id} deployed successfully.")
        @success_assumption_warning_shown = true
      end
      true
    end

    def exists?
      nil
    end

    def status
      @status ||= "Unknown"
      deploy_timed_out? ? "Timed out with status #{@status}" : @status
    end

    def type
      @type || self.class.name.split('::').last
    end

    def deploy_finished?
      deploy_failed? || deploy_succeeded? || deploy_timed_out?
    end

    def deploy_timed_out?
      return false unless @deploy_started
      !deploy_succeeded? && !deploy_failed? && (Time.now.utc - @deploy_started > timeout)
    end

    def tpr?
      false
    end

    # Expected values: :apply, :replace, :replace_force
    def deploy_method
      # TPRs must use update for now: https://github.com/kubernetes/kubernetes/issues/39906
      tpr? ? :replace : :apply
    end

    def status_data
      {
        group: group_name,
        name: name,
        status_string: status,
        exists: exists?,
        succeeded: deploy_succeeded?,
        failed: deploy_failed?,
        timed_out: deploy_timed_out?
      }
    end

    def group_name
      type.downcase.pluralize
    end

    def log_status
      @logger.info("[KUBESTATUS] #{JSON.dump(status_data)}")
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: false)
    end
  end
end
