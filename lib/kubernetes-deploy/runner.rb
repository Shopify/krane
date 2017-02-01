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
  service
).each do |subresource|
  require "kubernetes-deploy/kubernetes_resource/#{subresource}"
end

module KubernetesDeploy
  class Runner
    PREDEPLOY_SEQUENCE = %w(
      Cloudsql
      ConfigMap
      PersistentVolumeClaim
      Pod
    )

    # Things removed from default prune whitelist:
    # core/v1/Namespace -- not namespaced
    # core/v1/PersistentVolume -- not namespaced
    # core/v1/Endpoints -- managed by services
    # core/v1/PersistentVolumeClaim -- would delete data
    # core/v1/ReplicationController -- superseded by deployments/replicasets
    # extensions/v1beta1/ReplicaSet -- managed by deployments
    # core/v1/Secret -- should not committed / managed by shipit
    PRUNE_WHITELIST = %w(
      core/v1/ConfigMap
      core/v1/Pod
      core/v1/Service
      batch/v1/Job
      extensions/v1beta1/DaemonSet
      extensions/v1beta1/Deployment
      extensions/v1beta1/HorizontalPodAutoscaler
      extensions/v1beta1/Ingress
      apps/v1beta1/StatefulSet
    ).freeze

    def self.with_friendly_errors
      yield
    rescue FatalDeploymentError => error
      KubernetesDeploy.logger.fatal <<-MSG
#{error.class}: #{error.message}
  #{error.backtrace && error.backtrace.join("\n  ")}
MSG
      exit 1
    end

    def initialize(namespace:, current_sha:, context:, wait_for_completion:, template_dir:)
      @namespace = namespace
      @context = context
      @current_sha = current_sha
      @template_dir = File.expand_path(template_dir)
      # Max length of podname is only 63chars so try to save some room by truncating sha to 8 chars
      @id = current_sha[0...8] + "-#{SecureRandom.hex(4)}" if current_sha
      @wait_for_completion = wait_for_completion
    end

    def wait_for_completion?
      @wait_for_completion
    end

    def run
      @current_phase = 0
      phase_heading("Validating configuration")
      validate_configuration

      phase_heading("Configuring kubectl")
      set_kubectl_context
      validate_namespace

      phase_heading("Parsing deploy content")
      resources = discover_resources

      phase_heading("Checking initial resource statuses")
      resources.each(&:sync)

      phase_heading("Predeploying priority resources")
      predeploy_priority_resources(resources)

      phase_heading("Deploying all resources")
      deploy_resources(resources, prune: true)

      return unless wait_for_completion?
      wait_for_completion(resources)
      report_final_status(resources)
    end

    def template_variables
      {
        'current_sha' => @current_sha,
        'deployment_id' => @id,
      }
    end

    private

    def predeploy_priority_resources(resource_list)
      PREDEPLOY_SEQUENCE.each do |resource_type|
        matching_resources = resource_list.select { |r| r.type == resource_type }
        next if matching_resources.empty?
        deploy_resources(matching_resources)
        wait_for_completion(matching_resources)
        fail_count = matching_resources.count { |r| r.deploy_failed? || r.deploy_timed_out? }
        if fail_count > 0
          raise FatalDeploymentError, "#{fail_count} priority resources failed to deploy"
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
          resources << KubernetesResource.for_type(type, name, @namespace, tempfile)
          KubernetesDeploy.logger.info "Discovered template for #{resource_id}"
        end
      end
      resources
    end

    def discover_resource_via_dry_run(tempfile)
      resource_id, err, st = run_kubectl("create", "-f", tempfile.path, "--dry-run", "--output=name")
      raise FatalDeploymentError, "Dry run failed for template #{File.basename(tempfile.path)}." unless st.success?
      resource_id
    end

    def split_templates(filename)
      file_content = File.read(File.join(@template_dir, filename))
      rendered_content = render_template(filename, file_content)
      YAML.load_stream(rendered_content) do |doc|
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
        KubernetesDeploy.logger.error("The following resources failed to deploy: #{fail_list.join(", ")}")
        raise FatalDeploymentError, "#{fail_list.length} resources failed to deploy"
      end
    end

    def wait_for_completion(watched_resources)
      delay_sync_until = Time.now.utc
      started_at = delay_sync_until
      human_resources = watched_resources.map(&:id).join(", ")
      KubernetesDeploy.logger.info("Waiting for #{human_resources}")
      while watched_resources.present?
        if Time.now.utc < delay_sync_until
          sleep (delay_sync_until - Time.now.utc)
        end
        delay_sync_until = Time.now.utc + 3 # don't pummel the API if the sync is fast
        watched_resources.each(&:sync)
        newly_finished_resources, watched_resources = watched_resources.partition(&:deploy_finished?)
        newly_finished_resources.each do |resource|
          next unless resource.deploy_failed? || resource.deploy_timed_out?
          KubernetesDeploy.logger.error("#{resource.id} failed to deploy with status '#{resource.status}'.")
          KubernetesDeploy.logger.error("This script will continue to poll until the status of all resources deployed in this phase is resolved, but the deploy is now doomed and you may wish abort it.")
          KubernetesDeploy.logger.error(resource.status_data)
        end
      end

      watch_time = Time.now.utc - started_at
      KubernetesDeploy.logger.info("Spent #{watch_time.round(2)}s waiting for #{human_resources}")
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
        errors << "Kube config not found at #{ENV["KUBECONFIG"]}"
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
      end

      if @context.blank?
        errors << "Context must be specified"
      end

      raise FatalDeploymentError, "Configuration invalid: #{errors.join(", ")}" unless errors.empty?
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
      command = ["apply"]
      KubernetesDeploy.logger.info("Deploying resources:")

      # TPRs must use update for now: https://github.com/kubernetes/kubernetes/issues/39906
      tprs, resources = resources.partition(&:tpr?)
      update_tprs(tprs)

      resources.each do |r|
        KubernetesDeploy.logger.info("- #{r.id}")
        command.push("-f", r.file.path)
        r.deploy_started = Time.now.utc
      end

      if prune
        command.push("--prune", "--all")
        PRUNE_WHITELIST.each { |type| command.push("--prune-whitelist=#{type}") }
      end

      run_kubectl(*command)
    end

    def set_kubectl_context
      out, err, st = run_kubectl("config", "get-contexts", "-o", "name", namespaced: false)
      available_contexts = out.split("\n")
      if !st.success?
        raise FatalDeploymentError, err
      elsif !available_contexts.include?(@context)
        raise FatalDeploymentError, "Context #{@context} is not available. Valid contexts: #{available_contexts}"
      end

      _, err, st = run_kubectl("config", "use-context", @context, namespaced: false)
      raise FatalDeploymentError, "Kubectl config is not valid: #{err}" unless st.success?
      KubernetesDeploy.logger.info("Kubectl configured to use context #{@context}")
    end

    def validate_namespace
      _, _, st = run_kubectl("get", "namespace", @namespace, namespaced: false)
      raise FatalDeploymentError, "Failed to validate namespace #{@namespace}" unless st.success?
      KubernetesDeploy.logger.info("Namespace #{@namespace} validated")
    end

    def run_kubectl(*args, namespaced: true)
      args = args.unshift("kubectl")
      if namespaced
        raise FatalDeploymentError, "Namespace missing for namespaced command" unless @namespace
        args.push("--namespace=#{@namespace}")
      end
      KubernetesDeploy.logger.debug Shellwords.join(args)
      out, err, st = Open3.capture3(*args)
      KubernetesDeploy.logger.debug(out.shellescape)
      KubernetesDeploy.logger.warn(err) unless st.success?
      [out.chomp, err.chomp, st]
    end

    def phase_heading(phase_name)
      @current_phase += 1
      heading = "Phase #{@current_phase}: #{phase_name}"
      padding = (100.0 - heading.length)/2
      KubernetesDeploy.logger.info("")
      KubernetesDeploy.logger.info("#{'-' * padding.floor}#{heading}#{'-' * padding.ceil}")
    end

    def log_green(msg)
      STDOUT.puts "\033[0;32m#{msg}\x1b[0m\n" # green
    end
  end
end
