# frozen_string_literal: true
require 'open3'
require 'securerandom'
require 'erb'
require 'yaml'
require 'shellwords'
require 'tempfile'
require 'kubernetes-deploy/kubernetes_resource'
%w(
  cloudsql
  config_map
  deployment
  ingress
  persistent_volume_claim
  pod
  redis
  service
  pod_template
  bugsnag
  pod_disruption_budget
  replica_set
).each do |subresource|
  require "kubernetes-deploy/kubernetes_resource/#{subresource}"
end
require 'kubernetes-deploy/resource_watcher'
require 'kubernetes-deploy/kubectl'
require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/ejson_secret_provisioner'

module KubernetesDeploy
  class Runner
    include KubeclientBuilder

    PREDEPLOY_SEQUENCE = %w(
      Cloudsql
      Redis
      Bugsnag
      ConfigMap
      PersistentVolumeClaim
      Pod
    )
    PROTECTED_NAMESPACES = %w(
      default
      kube-system
      kube-public
    )

    # Things removed from default prune whitelist:
    # core/v1/Namespace -- not namespaced
    # core/v1/PersistentVolume -- not namespaced
    # core/v1/Endpoints -- managed by services
    # core/v1/PersistentVolumeClaim -- would delete data
    # core/v1/ReplicationController -- superseded by deployments/replicasets
    # extensions/v1beta1/ReplicaSet -- managed by deployments
    # core/v1/Secret -- should not committed / managed by shipit
    BASE_PRUNE_WHITELIST = %w(
      core/v1/ConfigMap
      core/v1/Pod
      core/v1/Service
      batch/v1/Job
      extensions/v1beta1/DaemonSet
      extensions/v1beta1/Deployment
      extensions/v1beta1/Ingress
      apps/v1beta1/StatefulSet
    ).freeze

    PRUNE_WHITELIST_V_1_5 = %w(extensions/v1beta1/HorizontalPodAutoscaler).freeze
    PRUNE_WHITELIST_V_1_6 = %w(autoscaling/v1/HorizontalPodAutoscaler).freeze

    def initialize(namespace:, context:, current_sha:, template_dir:, logger:, bindings: {})
      @namespace = namespace
      @context = context
      @current_sha = current_sha
      @template_dir = File.expand_path(template_dir)
      @logger = logger
      @bindings = bindings
      # Max length of podname is only 63chars so try to save some room by truncating sha to 8 chars
      @id = current_sha[0...8] + "-#{SecureRandom.hex(4)}" if current_sha
    end

    def run(verify_result: true, allow_protected_ns: false, prune: true)
      start = Time.now.utc
      @logger.reset

      @logger.phase_heading("Initializing deploy")
      validate_configuration(allow_protected_ns: allow_protected_ns, prune: prune)
      confirm_context_exists
      confirm_namespace_exists
      resources = discover_resources

      @logger.phase_heading("Checking initial resource statuses")
      resources.each(&:sync)
      resources.each { |r| @logger.info(r.pretty_status) }

      ejson = EjsonSecretProvisioner.new(
        namespace: @namespace,
        context: @context,
        template_dir: @template_dir,
        logger: @logger
      )
      if ejson.secret_changes_required?
        @logger.phase_heading("Deploying kubernetes secrets from #{EjsonSecretProvisioner::EJSON_SECRETS_FILE}")
        ejson.run
      end

      if deploy_has_priority_resources?(resources)
        @logger.phase_heading("Predeploying priority resources")
        start_priority_resource = Time.now.utc
        predeploy_priority_resources(resources)
        ::StatsD.measure('priority_resources.duration', statsd_duration(start_priority_resource), tags: statsd_tags)
      end

      @logger.phase_heading("Deploying all resources")
      if PROTECTED_NAMESPACES.include?(@namespace) && prune
        raise FatalDeploymentError, "Refusing to deploy to protected namespace '#{@namespace}' with pruning enabled"
      end

      if verify_result
        start_normal_resource = Time.now.utc
        deploy_resources(resources, prune: prune, verify: true)
        ::StatsD.measure('normal_resources.duration', statsd_duration(start_normal_resource), tags: statsd_tags)
        record_statuses(resources)
        success = resources.all?(&:deploy_succeeded?)
      else
        deploy_resources(resources, prune: prune, verify: false)
        @logger.summary.add_action("deployed #{resources.length} #{'resource'.pluralize(resources.length)}")
        warning = <<-MSG.strip_heredoc
          Deploy result verification is disabled for this deploy.
          This means the desired changes were communicated to Kubernetes, but the deploy did not make sure they actually succeeded.
        MSG
        @logger.summary.add_paragraph(ColorizedString.new(warning).yellow)
        success = true
      end
    rescue FatalDeploymentError => error
      @logger.summary.add_action(error.message)
      success = false
    ensure
      @logger.print_summary(success)
      status = success ? "success" : "failed"
      ::StatsD.measure('all_resources.duration', statsd_duration(start), tags: statsd_tags << "status:#{status}")
      success
    end

    def template_variables
      {
        'current_sha' => @current_sha,
        'deployment_id' => @id,
      }.merge(@bindings)
    end

    private

    def record_statuses(resources)
      successful_resources, failed_resources = resources.partition(&:deploy_succeeded?)
      fail_count = failed_resources.length
      success_count = successful_resources.length

      if success_count > 0
        @logger.summary.add_action("successfully deployed #{success_count} #{'resource'.pluralize(success_count)}")
        final_statuses = successful_resources.map(&:pretty_status).join("\n")
        @logger.summary.add_paragraph("#{ColorizedString.new('Successful resources').green}\n#{final_statuses}")
      end

      if fail_count > 0
        @logger.summary.add_action("failed to deploy #{fail_count} #{'resource'.pluralize(fail_count)}")
        failed_resources.each { |r| @logger.summary.add_paragraph(r.debug_message) }
      end
    end

    def versioned_prune_whitelist
      if server_major_version == "1.5"
        BASE_PRUNE_WHITELIST + PRUNE_WHITELIST_V_1_5
      else
        BASE_PRUNE_WHITELIST + PRUNE_WHITELIST_V_1_6
      end
    end

    def server_major_version
      @server_major_version ||= begin
        out, _, _ = kubectl.run('version', '--short')
        matchdata = /Server Version: v(?<version>\d\.\d)/.match(out)
        raise "Could not determine server version" unless matchdata[:version]
        matchdata[:version]
      end
    end

    # Inspect the file referenced in the kubectl stderr
    # to make it easier for developer to understand what's going on
    def find_bad_file_from_kubectl_output(stderr)
      # Output example:
      # Error from server (BadRequest): error when creating "/path/to/configmap-gqq5oh.yml20170411-33615-t0t3m":
      match = stderr.match(%r{BadRequest.*"(?<path>\/\S+\.ya?ml\S*)"})
      return unless match

      path = match[:path]
      if path.present? && File.file?(path)
        File.read(path)
      end
    end

    def deploy_has_priority_resources?(resources)
      resources.any? { |r| PREDEPLOY_SEQUENCE.include?(r.type) }
    end

    def predeploy_priority_resources(resource_list)
      PREDEPLOY_SEQUENCE.each do |resource_type|
        matching_resources = resource_list.select { |r| r.type == resource_type }
        next if matching_resources.empty?
        deploy_resources(matching_resources, verify: true)

        failed_resources = matching_resources.reject(&:deploy_succeeded?)
        fail_count = failed_resources.length
        if fail_count > 0
          failed_resources.each { |r| @logger.summary.add_paragraph(r.debug_message) }
          raise FatalDeploymentError, "Failed to deploy #{fail_count} priority #{'resource'.pluralize(fail_count)}"
        end
        @logger.blank_line
      end
    end

    def discover_resources
      resources = []
      @logger.info("Discovering templates:")
      Dir.foreach(@template_dir) do |filename|
        next unless filename.end_with?(".yml.erb", ".yml", ".yaml", ".yaml.erb")

        split_templates(filename) do |r_def|
          r = KubernetesResource.build(namespace: @namespace, context: @context, logger: @logger, definition: r_def)
          validate_template_via_dry_run(r.file_path, filename)
          resources << r
          @logger.info "  - #{r.id}"
        end
      end
      resources
    end

    def validate_template_via_dry_run(file_path, original_filename)
      command = ["create", "-f", file_path, "--dry-run", "--output=name"]
      _, err, st = kubectl.run(*command, log_failure: false)
      return if st.success?

      debug_msg = <<-DEBUG_MSG.strip_heredoc
        This usually means template '#{original_filename}' is not a valid Kubernetes template.
        Error from kubectl:
          #{err}
        Rendered template content:
      DEBUG_MSG
      debug_msg += File.read(file_path)
      @logger.summary.add_paragraph(debug_msg)

      raise FatalDeploymentError, "Kubectl dry run failed (command: #{Shellwords.join(command)})"
    end

    def split_templates(filename)
      file_content = File.read(File.join(@template_dir, filename))
      rendered_content = render_template(filename, file_content)
      YAML.load_stream(rendered_content) do |doc|
        yield doc unless doc.blank?
      end
    rescue Psych::SyntaxError => e
      debug_msg = <<-INFO.strip_heredoc
        Error message: #{e}

        Template content:
        ---
      INFO
      debug_msg += rendered_content
      @logger.summary.add_paragraph(debug_msg)
      raise FatalDeploymentError, "Template '#{filename}' cannot be parsed"
    end

    def record_apply_failure(err)
      file_content = find_bad_file_from_kubectl_output(err)
      debug_msg = <<-HELPFUL_MESSAGE.strip_heredoc
        This usually means one of your templates is invalid.
        Error from kubectl:
          #{err}
      HELPFUL_MESSAGE
      if file_content
        debug_msg += "Rendered template content:\n#{file_content}"
      end

      @logger.summary.add_paragraph(debug_msg)
    end

    def wait_for_completion(watched_resources, started_at)
      watcher = ResourceWatcher.new(watched_resources, logger: @logger, deploy_started_at: started_at)
      watcher.run
    end

    def render_template(filename, raw_template)
      return raw_template unless File.extname(filename) == ".erb"

      erb_template = ERB.new(raw_template)
      erb_binding = binding
      template_variables.each do |var_name, value|
        erb_binding.local_variable_set(var_name, value)
      end
      erb_template.result(erb_binding)
    rescue NameError => e
      @logger.summary.add_paragraph("Error from renderer:\n  #{e.message.tr("\n", ' ')}")
      raise FatalDeploymentError, "Template '#{filename}' cannot be rendered"
    end

    def validate_configuration(allow_protected_ns:, prune:)
      errors = []
      if ENV["KUBECONFIG"].blank? || !File.file?(ENV["KUBECONFIG"])
        errors << "Kube config not found at #{ENV['KUBECONFIG']}"
      end

      if @current_sha.blank?
        errors << "Current SHA must be specified"
      end

      if !File.directory?(@template_dir)
        errors << "Template directory `#{@template_dir}` doesn't exist"
      elsif Dir.entries(@template_dir).none? { |file| file =~ /\.ya?ml(\.erb)?$/ }
        errors << "`#{@template_dir}` doesn't contain valid templates (postfix .yml or .yml.erb)"
      end

      if @namespace.blank?
        errors << "Namespace must be specified"
      elsif PROTECTED_NAMESPACES.include?(@namespace)
        if allow_protected_ns && prune
          errors << "Refusing to deploy to protected namespace '#{@namespace}' with pruning enabled"
        elsif allow_protected_ns
          @logger.warn("You're deploying to protected namespace #{@namespace}, which cannot be pruned.")
          @logger.warn("Existing resources can only be removed manually with kubectl. " \
            "Removing templates from the set deployed will have no effect.")
          @logger.warn("***Please do not deploy to #{@namespace} unless you really know what you are doing.***")
        else
          errors << "Refusing to deploy to protected namespace '#{@namespace}'"
        end
      end

      if @context.blank?
        errors << "Context must be specified"
      end

      unless errors.empty?
        @logger.summary.add_paragraph(errors.map { |err| "- #{err}" }.join("\n"))
        raise FatalDeploymentError, "Configuration invalid"
      end

      @logger.info("All required parameters and files are present")
    end

    def deploy_resources(resources, prune: false, verify:)
      return if resources.empty?
      deploy_started_at = Time.now.utc

      if resources.length > 1
        @logger.info("Deploying resources:")
      else
        resource = resources.first
        @logger.info("Deploying #{resource.id} (timeout: #{resource.timeout}s)")
      end

      # Apply can be done in one large batch, the rest have to be done individually
      applyables, individuals = resources.partition { |r| r.deploy_method == :apply }

      individuals.each do |r|
        @logger.info("- #{r.id} (timeout: #{r.timeout}s)") if resources.length > 1
        r.deploy_started = Time.now.utc
        case r.deploy_method
        when :replace
          _, _, replace_st = kubectl.run("replace", "-f", r.file_path, log_failure: false)
        when :replace_force
          _, _, replace_st = kubectl.run("replace", "--force", "-f", r.file_path, log_failure: false)
        else
          # Fail Fast! This is a programmer mistake.
          raise ArgumentError, "Unexpected deploy method! (#{r.deploy_method.inspect})"
        end

        next if replace_st.success?
        # it doesn't exist so we can't replace it
        _, err, create_st = kubectl.run("create", "-f", r.file_path, log_failure: false)

        next if create_st.success?
        raise FatalDeploymentError, <<-MSG.strip_heredoc
          Failed to replace or create resource: #{r.id}
          #{err}
        MSG
      end

      apply_all(applyables, prune)
      wait_for_completion(resources, deploy_started_at) if verify
    end

    def apply_all(resources, prune)
      return unless resources.present?

      command = ["apply"]
      resources.each do |r|
        @logger.info("- #{r.id} (timeout: #{r.timeout}s)") if resources.length > 1
        command.push("-f", r.file_path)
        r.deploy_started = Time.now.utc
      end

      if prune
        command.push("--prune", "--all")
        versioned_prune_whitelist.each { |type| command.push("--prune-whitelist=#{type}") }
      end

      out, err, st = kubectl.run(*command, log_failure: false)
      if st.success?
        log_pruning(out) if prune
      else
        record_apply_failure(err)
        raise FatalDeploymentError, "Command failed: #{Shellwords.join(command)}"
      end
    end

    def log_pruning(kubectl_output)
      pruned = kubectl_output.scan(/^(.*) pruned$/)
      return unless pruned.present?

      @logger.info("The following resources were pruned: #{pruned.join(', ')}")
      @logger.summary.add_action("pruned #{pruned.length} #{'resource'.pluralize(pruned.length)}")
    end

    def confirm_context_exists
      out, err, st = kubectl.run("config", "get-contexts", "-o", "name",
        use_namespace: false, use_context: false, log_failure: false)
      available_contexts = out.split("\n")
      if !st.success?
        raise FatalDeploymentError, err
      elsif !available_contexts.include?(@context)
        raise FatalDeploymentError, "Context #{@context} is not available. Valid contexts: #{available_contexts}"
      end
      @logger.info("Context #{@context} found")
    end

    def confirm_namespace_exists
      _, _, st = kubectl.run("get", "namespace", @namespace, use_namespace: false, log_failure: false)
      raise FatalDeploymentError, "Namespace #{@namespace} not found" unless st.success?
      @logger.info("Namespace #{@namespace} found")
    end

    def kubectl
      @kubectl ||= Kubectl.new(namespace: @namespace, context: @context, logger: @logger, log_failure_by_default: true)
    end

    def statsd_tags
      %W(namespace:#{@namespace} sha:#{@current_sha} context:#{@context})
    end

    def statsd_duration(start_time)
      (Time.now.utc - start_time).round(1)
    end
  end
end
