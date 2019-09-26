# frozen_string_literal: true

require 'krane'
require 'thor'
require 'krane/cli/version_command'
require 'krane/cli/restart_command'
require 'krane/cli/run_command'
require 'krane/cli/render_command'
require 'krane/cli/deploy_command'
require 'krane/cli/global_deploy_command'

module Krane
  module CLI
    class Krane < Thor
      TIMEOUT_EXIT_CODE = 70
      FAILURE_EXIT_CODE = 1

      package_name "Krane"

      def self.expand_options(task_options)
        task_options.each { |option_name, config| method_option(option_name, config) }
      end

      desc("render", "Render templates")
      expand_options(RenderCommand::OPTIONS)
      def render
        rescue_and_exit do
          RenderCommand.from_options(options)
        end
      end

      desc("version", "Prints the version")
      expand_options(VersionCommand::OPTIONS)
      def version
        VersionCommand.from_options(options)
      end

      desc("restart NAMESPACE CONTEXT", "Restart the pods in one or more deployments")
      expand_options(RestartCommand::OPTIONS)
      def restart(namespace, context)
        rescue_and_exit do
          RestartCommand.from_options(namespace, context, options)
        end
      end

      desc("run NAMESPACE CONTEXT", "Run a pod that exits upon completing a task")
      expand_options(RunCommand::OPTIONS)
      def run_command(namespace, context)
        rescue_and_exit do
          RunCommand.from_options(namespace, context, options)
        end
      end

      desc("deploy NAMESPACE CONTEXT", "Ship resources to a namespace")
      expand_options(DeployCommand::OPTIONS)
      def deploy(namespace, context)
        rescue_and_exit do
          DeployCommand.from_options(namespace, context, options)
        end
      end

      desc("global-deploy CONTEXT", "Ship global resources to a cluster")
      expand_options(GlobalDeployCommand::OPTIONS)
      def global_deploy(context)
        rescue_and_exit do
          GlobalDeployCommand.from_options(context, options)
        end
      end

      def self.exit_on_failure?
        true
      end

      private

      def rescue_and_exit
        yield
      rescue KubernetesDeploy::DeploymentTimeoutError
        exit(TIMEOUT_EXIT_CODE)
      rescue KubernetesDeploy::FatalDeploymentError
        exit(FAILURE_EXIT_CODE)
      rescue KubernetesDeploy::DurationParser::ParsingError => e
        STDERR.puts(<<~ERROR_MESSAGE)
          Error parsing duration
          #{e.message}. Duration must be a full ISO8601 duration or time value (e.g. 300s, 10m, 1h)
        ERROR_MESSAGE
        exit(FAILURE_EXIT_CODE)
      end
    end
  end
end
