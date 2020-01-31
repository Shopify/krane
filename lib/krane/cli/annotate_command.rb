# frozen_string_literal: true

module Krane
  module CLI
    class AnnotateCommand
      OPTIONS = {
        "resources" => { type: :array, banner: "pod ingress", desc: 'A CSV string of all the resources to apply the annotation to',
                        default: [] },
        "filenames" => { type: :array, banner: 'config/deploy/production config/deploy/my-extra-resource.yml',
                         required: true, aliases: 'f', desc: 'Directories and files to annotate' },
        "stdin" => { type: :boolean, desc: "Read resources from stdin", default: false },
      }

      # ASSUMPTIONS/NOTES:
      #   - if no resource is specified, apply it to them all
      #     - would having a --all flag e better?
      #   - annotate requires YAML file format. so rendering must be done before: render -> annotate -> deploy
      #     - we can add a --render flag here to make it easier to interact with as well?
      #   - no formal tests yet, only manually tested by building the gem locally and trying it
      #     - gem build krane.gemspec && gem install ./krane-1.1.1.gem && krane annotate "key1:value2,key2:value2" --filenames test.yml --resources pod ingress

      def self.from_options(annotations, options)
        require 'krane/annotate_task'
        require 'krane/options_helper'

        pretty_annotations = {}
        arr_annotations = annotations.split(',') # TODO: catch error and return better err msg in .split?
        arr_annotations.each do |annotation|
          ann_value_pair = annotation.split(':') # TODO: catch error and return better err msg in .split?
          raise ArgumentError, "#{annotation} is not using `annotation:value` format" unless ann_value_pair.size == 2

          pretty_annotations[ann_value_pair[0]] = ann_value_pair[1]
        end

        # never mutate options directly
        filenames = options[:filenames].dup
        filenames << "-" if options[:stdin]
        if filenames.empty?
          raise Thor::RequiredArgumentMissingError, 'At least one of --filenames or --stdin must be set'
        end

        ::Krane::OptionsHelper.with_processed_template_paths(filenames, render_erb: true) do |paths|
          annotater = ::Krane::AnnotateTask.new(
            filenames: paths,
            resources: options[:resources].map(&:downcase),
            annotations: pretty_annotations,
          )
          annotater.run!(stream: STDOUT)
        end
      end
    end
  end
end
