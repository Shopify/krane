module KubernetesDeploy
  module KubectlWrapper
    extend self

    def run_kubectl(*args, context: nil, namespace: nil)
      args = args.unshift("kubectl")
      args.push("--context=#{context}") if context
      args.push("--namespace=#{namespace}") if namespace

      KubernetesDeploy.logger.debug Shellwords.join(args)
      out, err, st = Open3.capture3(*args)
      KubernetesDeploy.logger.debug(out.shellescape)

      unless st.success?
        KubernetesDeploy.logger.warn("The following command returned non-zero status: #{Shellwords.join(args)}")
        KubernetesDeploy.logger.warn(err.shellescape)
      end
      [out.chomp, err, st]
    end
  end
end
