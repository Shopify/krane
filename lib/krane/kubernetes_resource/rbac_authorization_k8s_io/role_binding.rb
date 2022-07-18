# frozen_string_literal: true
module Krane
  module RbacAuthorizationK8sIo
    class RoleBinding < KubernetesResource
      TIMEOUT = 30.seconds
      GROUP = ["rbac.authorization.k8s.io"]

      def status
        exists? ? "Created" : "Not Found"
      end

      def deploy_succeeded?
        exists?
      end

      def deploy_failed?
        false
      end

      def timeout_message
        UNUSUAL_FAILURE_MESSAGE
      end
    end
  end
end
