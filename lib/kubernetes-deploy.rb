require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/numeric/time'

require 'logger'
require 'kubernetes-deploy/runner'

module KubernetesDeploy
  class FatalDeploymentError < StandardError; end

  # Things removed from default prune whitelist:
  # core/v1/Namespace -- not namespaced
  # core/v1/PersistentVolume -- not namespaced
  # core/v1/Endpoints -- managed by services
  # core/v1/PersistentVolumeClaim -- would delete data
  # core/v1/ReplicationController -- superseded by deployments/replicasets
  # extensions/v1beta1/ReplicaSet -- managed by deployments
  # core/v1/Secret -- should not committed / managed by shipit
  PRUNE_WHITELIST = %w(
    core/v1/ConfigMap
    core/v1/Pod
    core/v1/Service
    batch/v1/Job
    extensions/v1beta1/DaemonSet
    extensions/v1beta1/Deployment
    extensions/v1beta1/HorizontalPodAutoscaler
    extensions/v1beta1/Ingress
    apps/v1beta1/StatefulSet
  ).freeze

  PREDEPLOY_SEQUENCE = %w(
    ConfigMap
    PersistentVolumeClaim
    Pod
  )

  def self.logger=(value)
    @logger = value
  end

  def self.logger
    @logger ||= begin
      l = Logger.new($stderr)
      l.level = level_from_env
      l.formatter = proc do |severity, _datetime, _progname, msg|
        case severity
        when "FATAL", "ERROR" then "\033[0;31m[#{severity}]\t#{msg}\x1b[0m\n" # red
        when "WARN" then "\033[0;33m[#{severity}]\t#{msg}\x1b[0m\n" # yellow
        when "INFO" then "\033[0;36m#{msg}\x1b[0m\n" # blue
        else "[#{severity}]\t#{msg}\n"
        end
      end
      l
    end
  end

  private

  def self.level_from_env
    return Logger::DEBUG if ENV["DEBUG"]

    if ENV["LEVEL"]
      Logger.const_get(ENV["LEVEL"].upcase)
    else
      Logger::INFO
    end
  end
end
