# frozen_string_literal: true

require 'krane/concerns/template_reporting'

module Krane
  class ResourceValidator
    extend Krane::StatsD::MeasureMethods
    include Krane::TemplateReporting

    delegate :logger, to: :@task_config
    attr_reader :statsd_tags

    def initialize(task_config:, prune_whitelist:, global_timeout:, current_sha: nil, selector:, statsd_tags:)
      @task_config = task_config
      @prune_whitelist = prune_whitelist
      @global_timeout = global_timeout
      @current_sha = current_sha
      @selector = selector
      @statsd_tags = statsd_tags
    end

    def validate(resources, prune:)
      validate_resources(resources, prune: prune, record_summary: true)
    end

    private

    def validate_all_resources(resources, prune: false, record_summary: true)
      validate_resources(resources, prune: prune, record_summary: record_summary)
    end
    measure_method(:validate_all_resources, 'normal_resources.duration')

    def validate_resources(resources, prune: false, record_summary: true)
      return if resources.empty?
      validate_started_at = Time.now.utc

      logger.info("Validating resources:")
      resources.each do |r|
        logger.info("  - #{r.id}")
      end

      validate_all(resources, prune)
    end

    def validate_all(resources, prune)
      return unless resources.present?
      command = %w(apply)
      command.push("--dry-run=server") # TODO: only good for 1.18, needs older version variants

      Dir.mktmpdir do |tmp_dir|
        resources.each do |r|
          FileUtils.symlink(r.file_path, tmp_dir)
          r.deploy_started_at = Time.now.utc
        end
        command.push("-f", tmp_dir)

        if prune && @prune_whitelist.present?
          command.push("--prune")
          if @selector
            command.push("--selector", @selector.to_s)
          else
            command.push("--all")
          end
          @prune_whitelist.each { |type| command.push("--prune-whitelist=#{type}") }
        end

        logger.info("will execute: #{command}")

        output_is_sensitive = resources.any?(&:sensitive_template_content?)
        global_mode = resources.all?(&:global?)
        out, err, st = kubectl.run(*command, log_failure: false, output_is_sensitive: output_is_sensitive,
          attempts: 2, use_namespace: !global_mode)

        if st.success?
          logger.info("looks like it worked?")
          logger.info("out: #{out}")
          logger.info("err: #{err}")
        else
          logger.info("bu. it failed. now what?")
          logger.info("out: #{out}")
          logger.info("err: #{err}")
          # TODO: flag individual resources
          raise Exception.new, "Command failed: #{Shellwords.join(command)}" # TODO: get a better exception class here
        end
      end
    end
    measure_method(:validate_all)

    def kubectl
      @kubectl ||= Kubectl.new(task_config: @task_config, log_failure_by_default: true)
    end
  end
end
