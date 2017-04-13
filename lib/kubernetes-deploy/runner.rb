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
).each do |subresource|
  require "kubernetes-deploy/kubernetes_resource/#{subresource}"
end
require 'kubernetes-deploy/resource_watcher'
require "kubernetes-deploy/ui_helpers"
require 'kubernetes-deploy/kubectl'
require 'kubernetes-deploy/kubeclient_builder'
require 'kubernetes-deploy/ejson_secret_provisioner'

module KubernetesDeploy
  class Runner
    include UIHelpers
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

    def self.with_friendly_errors
      yield
    rescue FatalDeploymentError => error
      KubernetesDeploy.logger.fatal <<-MSG
#{error.class}: #{error.message}
  #{error.backtrace && error.backtrace.join("\n  ")}
MSG
      exit 1
    end

    def initialize(namespace:, current_sha:, context:, template_dir:,
      wait_for_completion:, allow_protected_ns: false, prune: true, bindings: {})
      @namespace = namespace
      @context = context
      @current_sha = current_sha
      @template_dir = File.expand_path(template_dir)
      # Max length of podname is only 63chars so try to save some room by truncating sha to 8 chars
      @id = current_sha[0...8] + "-#{SecureRandom.hex(4)}" if current_sha
      @wait_for_completion = wait_for_completion
      @allow_protected_ns = allow_protected_ns
      @prune = prune
      @bindings = bindings
    end

    def wait_for_completion?
      @wait_for_completion
    end

    def allow_protected_ns?
      @allow_protected_ns
    end

    def run
      phase_heading("Validating configuration")
      validate_configuration

      phase_heading("Identifying deployment target")
      confirm_context_exists
      confirm_namespace_exists

      phase_heading("Parsing deploy content")
      resources = discover_resources

      phase_heading("Checking initial resource statuses")
      resources.each(&:sync)

      ejson = EjsonSecretProvisioner.new(
        namespace: @namespace,
        template_dir: @template_dir,
        client: build_v1_kubeclient(@context)
      )
      if ejson.secret_changes_required?
        phase_heading("Deploying kubernetes secrets from #{EjsonSecretProvisioner::EJSON_SECRETS_FILE}")
        ejson.run
      end

      phase_heading("Predeploying priority resources")
      predeploy_priority_resources(resources)

      phase_heading("Deploying all resources")
      if PROTECTED_NAMESPACES.include?(@namespace) && @prune
        raise FatalDeploymentError, "Refusing to deploy to protected namespace '#{@namespace}' with pruning enabled"
      end

      deploy_resources(resources, prune: @prune)

      return unless wait_for_completion?
      wait_for_completion(resources)
      report_final_status(resources)
    end

    def template_variables
      {
        'current_sha' => @current_sha,
        'deployment_id' => @id,
      }.merge(@bindings)
    end

    private

    def versioned_prune_whitelist
      if server_major_version == "1.5"
        BASE_PRUNE_WHITELIST + PRUNE_WHITELIST_V_1_5
      else
        BASE_PRUNE_WHITELIST + PRUNE_WHITELIST_V_1_6
      end
    end

    def server_major_version
      @server_major_version ||= begin
        out, _, _ = run_kubectl('version', '--short')
        matchdata = /Server Version: v(?<version>\d\.\d)/.match(out)
        raise "Could not determine server version" unless matchdata[:version]
        matchdata[:version]
      end
    end

    # Inspect the file referenced in the kubectl stderr
    # to make it easier for developer to understand what's going on
    def inspect_kubectl_out_for_files(stderr)
      # Output example:
      # Error from server (BadRequest): error when creating "/path/to/configmap-gqq5oh.yml20170411-33615-t0t3m":
      match = stderr.match(%r{BadRequest.*"(?<path>\/\S+\.yml\S+)"})
      return unless match

      path = match[:path]
      if path.present? && File.file?(path)
        suspicious_file = File.read(path)
        KubernetesDeploy.logger.warn("Inspecting the file mentioned in the error message (#{path})")
        KubernetesDeploy.logger.warn(suspicious_file)
      else
        KubernetesDeploy.logger.warn("Detected a file (#{path.inspect}) referenced in the kubectl stderr " \
          "but was unable to inspect it")
      end
    end

    def predeploy_priority_resources(resource_list)
      PREDEPLOY_SEQUENCE.each do |resource_type|
        matching_resources = resource_list.select { |r| r.type == resource_type }
        next if matching_resources.empty?
        deploy_resources(matching_resources)
        wait_for_completion(matching_resources)
        fail_list = matching_resources.select { |r| r.deploy_failed? || r.deploy_timed_out? }.map(&:id)
        unless fail_list.empty?
          raise FatalDeploymentError, "The following priority resources failed to deploy: #{fail_list.join(', ')}"
        end
      end
    end

    def discover_resources
      resources = []
      Dir.foreach(@template_dir) do |filename|
        next unless filename.end_with?(".yml.erb", ".yml")

        split_templates(filename) do |tempfile|
          resource_id = discover_resource_via_dry_run(tempfile)
          type, name = resource_id.split("/", 2) # e.g. "pod/web-198612918-dzvfb"
          resources << KubernetesResource.for_type(type, name, @namespace, @context, tempfile)
          KubernetesDeploy.logger.info "Discovered template for #{resource_id}"
        end
      end
      resources
    end

    def discover_resource_via_dry_run(tempfile)
      resource_id, _err, st = run_kubectl("create", "-f", tempfile.path, "--dry-run", "--output=name")
      raise FatalDeploymentError, "Dry run failed for template #{File.basename(tempfile.path)}." unless st.success?
      resource_id
    end

    def split_templates(filename)
      file_content = File.read(File.join(@template_dir, filename))
      rendered_content = render_template(filename, file_content)
      YAML.load_stream(rendered_content) do |doc|
        next if doc.blank?

        f = Tempfile.new(filename)
        f.write(YAML.dump(doc))
        f.close
        yield f
      end
    rescue Psych::SyntaxError => e
      KubernetesDeploy.logger.error(rendered_content)
      raise FatalDeploymentError, "Template #{filename} cannot be parsed: #{e.message}"
    end

    def report_final_status(resources)
      if resources.all?(&:deploy_succeeded?)
        log_green("Deploy succeeded!")
      else
        fail_list = resources.select { |r| r.deploy_failed? || r.deploy_timed_out? }.map(&:id)
        raise FatalDeploymentError, "The following resources failed to deploy: #{fail_list.join(', ')}"
      end
    end

    def wait_for_completion(watched_resources)
      watcher = ResourceWatcher.new(watched_resources)
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
    end

    def validate_configuration
      errors = []
      if ENV["KUBECONFIG"].blank? || !File.file?(ENV["KUBECONFIG"])
        errors << "Kube config not found at #{ENV['KUBECONFIG']}"
      end

      if @current_sha.blank?
        errors << "Current SHA must be specified"
      end

      if !File.directory?(@template_dir)
        errors << "Template directory `#{@template_dir}` doesn't exist"
      elsif Dir.entries(@template_dir).none? { |file| file =~ /\.yml(\.erb)?$/ }
        errors << "`#{@template_dir}` doesn't contain valid templates (postfix .yml or .yml.erb)"
      end

      if @namespace.blank?
        errors << "Namespace must be specified"
      elsif PROTECTED_NAMESPACES.include?(@namespace)
        if allow_protected_ns? && @prune
          errors << "Refusing to deploy to protected namespace '#{@namespace}' with pruning enabled"
        elsif allow_protected_ns?
          warning = <<-WARNING.strip_heredoc
          You're deploying to protected namespace #{@namespace}, which cannot be pruned.
          Existing resources can only be removed manually with kubectl. Removing templates from the set deployed will have no effect.
          ***Please do not deploy to #{@namespace} unless you really know what you are doing.***
          WARNING
          KubernetesDeploy.logger.warn(warning)
        else
          errors << "Refusing to deploy to protected namespace '#{@namespace}'"
        end
      end

      if @context.blank?
        errors << "Context must be specified"
      end

      raise FatalDeploymentError, "Configuration invalid: #{errors.join(', ')}" unless errors.empty?
      KubernetesDeploy.logger.info("All required parameters and files are present")
    end

    def update_tprs(resources)
      resources.each do |r|
        KubernetesDeploy.logger.info("- #{r.id}")
        r.deploy_started = Time.now.utc
        _, _, st = run_kubectl("replace", "-f", r.file.path)

        unless st.success?
          # it doesn't exist so we can't replace it
          run_kubectl("create", "-f", r.file.path)
        end
      end
    end

    def deploy_resources(resources, prune: false)
      KubernetesDeploy.logger.info("Deploying resources:")

      # TPRs must use update for now: https://github.com/kubernetes/kubernetes/issues/39906
      tprs, resources = resources.partition(&:tpr?)
      update_tprs(tprs)
      return unless resources.present?

      command = ["apply"]
      resources.each do |r|
        KubernetesDeploy.logger.info("- #{r.id}")
        command.push("-f", r.file.path)
        r.deploy_started = Time.now.utc
      end

      if prune
        command.push("--prune", "--all")
        versioned_prune_whitelist.each { |type| command.push("--prune-whitelist=#{type}") }
      end

      _, err, st = run_kubectl(*command)
      unless st.success?
        inspect_kubectl_out_for_files(err)
        raise FatalDeploymentError, <<-MSG
"The following command failed: #{Shellwords.join(command)}"
#{err}
MSG
      end
    end

    def confirm_context_exists
      out, err, st = run_kubectl("config", "get-contexts", "-o", "name", namespaced: false, with_context: false)
      available_contexts = out.split("\n")
      if !st.success?
        raise FatalDeploymentError, err
      elsif !available_contexts.include?(@context)
        raise FatalDeploymentError, "Context #{@context} is not available. Valid contexts: #{available_contexts}"
      end
      KubernetesDeploy.logger.info("Context #{@context} found")
    end

    def confirm_namespace_exists
      _, _, st = run_kubectl("get", "namespace", @namespace, namespaced: false)
      raise FatalDeploymentError, "Namespace #{@namespace} not found" unless st.success?
      KubernetesDeploy.logger.info("Namespace #{@namespace} found")
    end

    def run_kubectl(*args, namespaced: true, with_context: true)
      if namespaced
        raise KubectlError, "Namespace missing for namespaced command" if @namespace.blank?
      end

      if with_context
        raise KubectlError, "Explicit context is required to run this command" if @context.blank?
      end

      Kubectl.run_kubectl(*args, namespace: @namespace, context: @context)
    end
  end
end
