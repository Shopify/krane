# frozen_string_literal: true

require 'googleauth'
module KubernetesDeploy
  module KubeclientBuilder
    class GoogleFriendlyConfig < Kubeclient::Config
      def fetch_user_auth_options(user)
        if user.dig('auth-provider', 'name') == 'gcp'
          { bearer_token: new_token }
        else
          super
        end
      end

      def self.read(filename)
        new(YAML.safe_load(File.read(filename), [Time]), File.dirname(filename))
      end

      def new_token
        scopes = ['https://www.googleapis.com/auth/cloud-platform']
        authorization = Google::Auth.get_application_default(scopes)

        authorization.apply({})

        authorization.access_token

      rescue Signet::AuthorizationError => e
        err_message = json_error_message(e.response.body) || e.message
        raise KubeException.new(e.response.status, err_message, e.response.body)
      end

      private

      def json_error_message(body)
        json_error_msg = begin
          JSON.parse(body || '') || {}
        rescue JSON::ParserError
          {}
        end
        json_error_msg['message']
      end
    end
  end
end
