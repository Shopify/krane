# frozen_string_literal: true

module Krane
  module CLI
    class VersionCommand

      OPTIONS = {
        #check: { type: :string, banner: 'context',
        #  desc: 'Verify if Krane is compatible with your local and remote k8s versions.' }
      }

      def self.from_options(options)
        # This code will use the Validtor object being added in a different PR.
        #if options[:check]
        #  $stderr.puts("Checking if context: #{options[:check]} is valid")
        #end
        puts("krane #{KubernetesDeploy::VERSION}")
      end
    end
  end
end
