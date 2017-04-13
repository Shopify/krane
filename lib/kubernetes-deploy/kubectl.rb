# frozen_string_literal: true

module KubernetesDeploy
  module Kubectl
    def self.run_kubectl(*args, namespace:, context:, log_failure: true)
      args = args.unshift("kubectl")
      args.push("--namespace=#{namespace}") if namespace.present?
      args.push("--context=#{context}")     if context.present?

      KubernetesDeploy.logger.debug Shellwords.join(args)
      out, err, st = Open3.capture3(*args)
      KubernetesDeploy.logger.debug(out.shellescape)
      if !st.success? && log_failure
        KubernetesDeploy.logger.warn("The following command failed: #{Shellwords.join(args)}")
        KubernetesDeploy.logger.warn(err)
      end
      [out.chomp, err.chomp, st]
    end
  end
end
