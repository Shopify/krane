# frozen_string_literal: true

module Krane
  module CLI
    class VersionCommand
      OPTIONS = {
        check: {
          type: :string,
          banner: 'context',
          desc: 'Verify if Krane is compatible with your local and remote k8s versions.',
          lazy_default: '', # Thor will use the flag name as the default value
        },
      }

      def self.from_options(options)
        if options[:check]
          config = KubernetesDeploy::TaskConfig.new(options[:check], nil)
          config.logger.info("Checking if context: #{options[:check]} is valid")
          kubectl = KubernetesDeploy::Kubectl.new(namespace: "default", context: config.context,
              logger: config.logger, log_failure_by_default: false) if config.context.present?

          kubeclient = KubernetesDeploy::KubeclientBuilder.new

          validator = KubernetesDeploy::TaskConfigValidator.new(config, kubectl, kubeclient,
            warning_as_error: true, skip: [:validate_namespace_exists])
          if validator.valid?
            config.logger.info("Context #{config.context} is valid")
          else
            validator.errors.each { |m| config.logger.error(m) }
            exit(1)
          end
        end
        puts("krane #{KubernetesDeploy::VERSION}")
      end
    end
  end
end
