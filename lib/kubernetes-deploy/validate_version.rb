# frozen_string_literal: true
require 'yaml'

module KubernetesDeploy
  class ValidateVersion

    def self.confirm_version(kubectl)
      out, err, st = kubectl.run("version", "--short", use_namespace: false,
        use_context: false, log_failure: false)
      if !st.success?
        raise FatalDeploymentError, err
      elsif
        server_version = YAML.load(out)['Server Version']
        if not Gem::Version.new(server_version[1..-1]) > Gem::Version.new('1.6')
          raise FatalDeploymentError, 'Versions before 1.6 are not supported'
        end
      end
    end
  end
end