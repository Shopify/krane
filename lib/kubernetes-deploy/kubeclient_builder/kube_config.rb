# frozen_string_literal: true

require 'googleauth'
module KubernetesDeploy
  class KubeclientBuilder
    class KubeConfig < Kubeclient::Config
      attr_accessor :filename
      def self.read(filename)
        parsed = YAML.safe_load(File.read(filename), [Date, Time])
        config = new(parsed, File.dirname(filename))
        config.filename = filename
        config
      end

      def fetch_user_auth_options(user)
        if user.dig('auth-provider', 'name') == 'gcp'
          { bearer_token: Kubeclient::GoogleApplicationDefaultCredentials.token }
        else
          super
        end
      end
    end
  end
end
