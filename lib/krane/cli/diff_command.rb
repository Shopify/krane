# frozen_string_literal: true

module Krane
    module CLI
      class DiffCommand
        OPTIONS = {
          "bindings" => { type: :string, banner: "bindings",
                             desc: "(format: k1=v1,k2=v2, JSON string or file (JSON or YAML) path prefixed by '@')" },
          "template_paths" => { type: :array, aliases: "-f", default: ["."],
                             desc: "space separated list of template directories and/or filenames (default: current directory)" },
          "selector" => { type: :string, banner: "'label=value'",
                          desc: "Select workloads by selector(s)" },
        }

        def self.from_options(namespace, context, options)
          require 'kubernetes-deploy/diff_task'
          require 'kubernetes-deploy/bindings_parser'
          require 'kubernetes-deploy/label_selector'
          require 'optparse'

          parser = KubernetesDeploy::BindingsParser.new
          parser.add(options[:bindings]) if options[:bindings]
          logger = KubernetesDeploy::FormattedLogger.build(namespace, context)
          selector = KubernetesDeploy::LabelSelector.parse(options[:selector]) if options[:selector]

          runner = KubernetesDeploy::DiffTask.new(
            namespace: namespace,
            context: context,
            current_sha: ENV["REVISION"],
            template_paths: options[:template_paths],
            bindings: parser.parse,
            logger: logger,
            selector: selector
          )

          runner.run!(stream: STDOUT)
        end
      end
    end
  end
