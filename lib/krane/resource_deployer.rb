# frozen_string_literal: true

require 'krane/resource_watcher'
require 'krane/concerns/template_reporting'

module Krane
  class ResourceDeployer
    extend Krane::StatsD::MeasureMethods
    include Krane::TemplateReporting

    delegate :logger, to: :@task_config
    attr_reader :statsd_tags

    def initialize(task_config:, prune_whitelist:, max_watch_seconds:, selector:, statsd_tags:)
      @task_config = task_config
      @prune_whitelist = prune_whitelist
      @max_watch_seconds = max_watch_seconds
      @selector = selector
      @statsd_tags = statsd_tags
    end

    def deploy!(resources, verify_result, prune)
      if verify_result
        deploy_all_resources(resources, prune: prune, verify: true)
        failed_resources = resources.reject(&:deploy_succeeded?)
        success = failed_resources.empty?
        if !success && failed_resources.all?(&:deploy_timed_out?)
          raise DeploymentTimeoutError
        end
        raise FatalDeploymentError unless success
      else
        deploy_all_resources(resources, prune: prune, verify: false)
        logger.summary.add_action("deployed #{resources.length} #{'resource'.pluralize(resources.length)}")
        warning = <<~MSG
          Deploy result verification is disabled for this deploy.
          This means the desired changes were communicated to Kubernetes, but the deploy did not make sure they actually succeeded.
        MSG
        logger.summary.add_paragraph(ColorizedString.new(warning).yellow)
      end
    end

    def predeploy_priority_resources(resource_list, predeploy_sequence)
      bare_pods = resource_list.select { |resource| resource.is_a?(Pod) }
      if bare_pods.count == 1
        bare_pods.first.stream_logs = true
      end

      predeploy_sequence.each do |resource_type|
        matching_resources = resource_list.select { |r| r.type == resource_type }
        next if matching_resources.empty?
        deploy_resources(matching_resources, verify: true, record_summary: false)

        failed_resources = matching_resources.reject(&:deploy_succeeded?)
        fail_count = failed_resources.length
        if fail_count > 0
          Krane::Concurrency.split_across_threads(failed_resources) do |r|
            r.sync_debug_info(kubectl)
          end
          failed_resources.each { |r| logger.summary.add_paragraph(r.debug_message) }
          raise FatalDeploymentError, "Failed to deploy #{fail_count} priority #{'resource'.pluralize(fail_count)}"
        end
        logger.blank_line
      end
    end
    measure_method(:predeploy_priority_resources, 'priority_resources.duration')

    private

    def deploy_all_resources(resources, prune: false, verify:, record_summary: true)
      deploy_resources(resources, prune: prune, verify: verify, record_summary: record_summary)
    end
    measure_method(:deploy_all_resources, 'normal_resources.duration')

    def deploy_resources(resources, prune: false, verify:, record_summary: true)
      return if resources.empty?
      deploy_started_at = Time.now.utc

      if resources.length > 1
        logger.info("Deploying resources:")
        resources.each do |r|
          logger.info("- #{r.id} (#{r.pretty_timeout_type})")
        end
      else
        resource = resources.first
        logger.info("Deploying #{resource.id} (#{resource.pretty_timeout_type})")
      end

      # Apply can be done in one large batch, the rest have to be done individually
      applyables, individuals = resources.partition { |r| r.deploy_method == :apply }
      # Prunable resources should also applied so that they can  be pruned
      pruneable_types = @prune_whitelist.map { |t| t.split("/").last }
      applyables += individuals.select { |r| pruneable_types.include?(r.type) }

      individuals.each do |individual_resource|
        individual_resource.deploy_started_at = Time.now.utc

        case individual_resource.deploy_method
        when :create
          err, status = create_resource(individual_resource)
        when :replace
          err, status = replace_or_create_resource(individual_resource)
        when :replace_force
          err, status = replace_or_create_resource(individual_resource, force: true)
        else
          # Fail Fast! This is a programmer mistake.
          raise ArgumentError, "Unexpected deploy method! (#{individual_resource.deploy_method.inspect})"
        end

        next if status.success?

        raise FatalDeploymentError, <<~MSG
          Failed to replace or create resource: #{individual_resource.id}
          #{individual_resource.sensitive_template_content? ? '<suppressed sensitive output>' : err}
        MSG
      end

      apply_all(applyables, prune)

      if verify
        watcher = Krane::ResourceWatcher.new(resources: resources, deploy_started_at: deploy_started_at,
          timeout: @max_watch_seconds, task_config: @task_config)
        watcher.run(record_summary: record_summary)
      end
    end

    def apply_all(resources, prune)
      return unless resources.present?
      command = %w(apply)

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

        output_is_sensitive = resources.any?(&:sensitive_template_content?)
        global_mode = resources.all?(&:global?)
        out, err, st = kubectl.run(*command, log_failure: false, output_is_sensitive: output_is_sensitive,
          use_namespace: !global_mode)

        if st.success?
          log_pruning(out) if prune
        else
          record_apply_failure(err, resources: resources)
          raise FatalDeploymentError, "Command failed: #{Shellwords.join(command)}"
        end
      end
    end
    measure_method(:apply_all)

    def log_pruning(kubectl_output)
      pruned = kubectl_output.scan(/^(.*) pruned$/)
      return unless pruned.present?

      logger.info("The following resources were pruned: #{pruned.join(', ')}")
      logger.summary.add_action("pruned #{pruned.length} #{'resource'.pluralize(pruned.length)}")
    end

    def record_apply_failure(err, resources: [])
      warn_msg = "WARNING: Any resources not mentioned in the error(s) below were likely created/updated. " \
        "You may wish to roll back this deploy."
      logger.summary.add_paragraph(ColorizedString.new(warn_msg).yellow)

      unidentified_errors = []
      filenames_with_sensitive_content = resources
        .select(&:sensitive_template_content?)
        .map { |r| File.basename(r.file_path) }

      server_dry_run_validated_resource = resources
        .select(&:server_dry_run_validated?)
        .map { |r| File.basename(r.file_path) }

      err.each_line do |line|
        bad_files = find_bad_files_from_kubectl_output(line)
        unless bad_files.present?
          unidentified_errors << line
          next
        end

        bad_files.each do |f|
          err_msg = f[:err]
          if filenames_with_sensitive_content.include?(f[:filename])
            # Hide the error and template contents in case it has sensitive information
            # we display full error messages as we assume there's no sensitive info leak after server-dry-run
            err_msg = "SUPPRESSED FOR SECURITY" unless server_dry_run_validated_resource.include?(f[:filename])
            record_invalid_template(logger: logger, err: err_msg, filename: f[:filename], content: nil)
          else
            record_invalid_template(logger: logger, err: err_msg, filename: f[:filename], content: f[:content])
          end
        end
      end
      return unless unidentified_errors.any?

      if (filenames_with_sensitive_content - server_dry_run_validated_resource).present?
        warn_msg = "WARNING: There was an error applying some or all resources. The raw output may be sensitive and " \
          "so cannot be displayed."
        logger.summary.add_paragraph(ColorizedString.new(warn_msg).yellow)
      else
        heading = ColorizedString.new('Unidentified error(s):').red
        msg = FormattedLogger.indent_four(unidentified_errors.join)
        logger.summary.add_paragraph("#{heading}\n#{msg}")
      end
    end

    def replace_or_create_resource(resource, force: false)
      args = if force
        ["replace", "--force", "--cascade", "-f", resource.file_path]
      else
        ["replace", "-f", resource.file_path]
      end

      _, err, status = kubectl.run(*args, log_failure: false, output_is_sensitive: resource.sensitive_template_content?,
        raise_if_not_found: true, use_namespace: !resource.global?)

      [err, status]
    rescue Krane::Kubectl::ResourceNotFoundError
      # it doesn't exist so we can't replace it, we try to create it
      create_resource(resource)
    end

    def create_resource(resource)
      out, err, status = kubectl.run("create", "-f", resource.file_path, log_failure: false,
        output: 'json', output_is_sensitive: resource.sensitive_template_content?,
        use_namespace: !resource.global?)

      # For resources that rely on a generateName attribute, we get the `name` from the result of the call to `create`
      # We must explicitly set this name value so that the `apply` step for pruning can run successfully
      if status.success? && resource.uses_generate_name?
        resource.use_generated_name(JSON.parse(out))
      end

      [err, status]
    end

    # Inspect the file referenced in the kubectl stderr
    # to make it easier for developer to understand what's going on
    def find_bad_files_from_kubectl_output(line)
      # stderr often contains one or more lines like the following, from which we can extract the file path(s):
      # Error from server (TypeOfError): error when creating "/path/to/service-gqq5oh.yml": Service "web" is invalid:

      line.scan(%r{"(/\S+\.ya?ml\S*)"}).each_with_object([]) do |matches, bad_files|
        matches.each do |path|
          content = File.read(path) if File.file?(path)
          bad_files << { filename: File.basename(path), err: line, content: content }
        end
      end
    end

    def kubectl
      @kubectl ||= Kubectl.new(task_config: @task_config, log_failure_by_default: true)
    end
  end
end
