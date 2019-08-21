# frozen_string_literal: true

require 'krane/cli_commands/deploy'
require 'krane/cli_commands/version'
require 'thor'

module Krane
  class CLI < Thor
    def self.expand_options(task_options)
      task_options.each { |option_name, config| method_option(option_name, config) }
    end

    desc("version", "Prints the version")
    expand_options(Krane::CLICommands::Version::OPTIONS)
    def version
      Krane::CLICommands::Version.from_options(options)
    end

    desc("deploy NAMESPACE CONTEXT", "Deploy your app to your namespace")
    expand_options(Krane::CLICommands::Deploy::OPTIONS)
    def deploy(namespace, context)
      convert_exceptions_to_exit_codes do
        Krane::CLICommands::Deploy.from_options(namespace, context, options)
      end
    end

    def self.exit_on_failure?
      true
    end

    private

    def convert_exceptions_to_exit_codes
      yield
    rescue KubernetesDeploy::DeploymentTimeoutError
      exit(70)
    rescue KubernetesDeploy::FatalDeploymentError
      exit(1)
    end
  end
end
