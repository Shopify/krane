# frozen_string_literal: true
module Krane
  module Policy
    class PodDisruptionBudget < KubernetesResource
      TIMEOUT = 10.seconds

      def status
        exists? ? "Available" : "Not Found"
      end

      def deploy_succeeded?
        exists? && observed_generation == current_generation
      end

      def deploy_method
        # Required until https://github.com/kubernetes/kubernetes/issues/45398 changes
        uses_generate_name? ? :create : :replace_force
      end

      def timeout_message
        UNUSUAL_FAILURE_MESSAGE
      end
    end
  end
end
