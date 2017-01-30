require 'json'
require 'open3'
require 'shellwords'

module KubernetesDeploy
  class KubernetesResource

    attr_reader :name, :namespace, :file
    attr_writer :type, :deploy_started

    TIMEOUT = 5.minutes

    def self.for_type(type, name, namespace, file)
      case type
      when 'cloudsql' then Cloudsql.new(name, namespace, file)
      when 'configmap' then ConfigMap.new(name, namespace, file)
      when 'deployment' then Deployment.new(name, namespace, file)
      when 'pod' then Pod.new(name, namespace, file)
      when 'ingress' then Ingress.new(name, namespace, file)
      when 'persistentvolumeclaim' then PersistentVolumeClaim.new(name, namespace, file)
      when 'service' then Service.new(name, namespace, file)
      else self.new(name, namespace, file).tap { |r| r.type = type }
      end
    end

    def initialize(name, namespace, file)
      # subclasses must also set these
      @name, @namespace, @file = name, namespace, file
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
        KubernetesDeploy.logger.warn("Don't know how to monitor resources of type #{type}. Assuming #{id} deployed successfully.")
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
      !deploy_succeeded? && !deploy_failed? && (Time.now.utc - @deploy_started > self.class::TIMEOUT)
    end

    def tpr?
      false
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
      type + "s"
    end

    def run_kubectl(*args)
      raise FatalDeploymentError, "Namespace missing for namespaced command" if namespace.blank?
      args = args.unshift("kubectl").push("--namespace=#{namespace}")
      KubernetesDeploy.logger.debug Shellwords.join(args)
      out, err, st = Open3.capture3(*args)
      KubernetesDeploy.logger.debug(out.shellescape)
      KubernetesDeploy.logger.debug("[ERROR] #{err.shellescape}") unless st.success?
      [out.chomp, st]
    end

    def log_status
      STDOUT.puts "[KUBESTATUS] #{JSON.dump(status_data)}"
    end
  end
end
