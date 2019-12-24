# frozen_string_literal: true
require 'securerandom'
require 'krane/deploy_task'

module FixtureDeployHelper
  EJSON_FILENAME = Krane::EjsonSecretProvisioner::EJSON_SECRETS_FILE

  # Deploys the specified set of fixtures via Krane::DeployTask.
  #
  # Optionally takes an array of filenames belonging to the fixture, and deploys that subset only.
  # Example:
  # # Deploys hello-cloud/redis.yml
  # deploy_fixtures("hello-cloud", ["redis.yml"])
  #
  # Optionally yields a hash of the fixture's loaded templates that can be modified before the deploy is executed.
  # The following example illustrates the format of the yielded hash:
  #  {
  #    "web.yml.erb" => {
  #      "Ingress" => [loaded_ingress_yaml],
  #      "Service" => [loaded_service_yaml],
  #      "Deployment" => [loaded_service_yaml]
  #    }
  #  }
  #
  # Example:
  # # The following will deploy the "hello-cloud" fixture set, but with the unmanaged pod modified to use a bad image
  #   deploy_fixtures("hello-cloud") do |fixtures|
  #     pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
  #     pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
  #   end
  def deploy_fixtures(set, subset: nil, **args) # extra args are passed through to deploy_dirs_without_profiling
    fixtures = load_fixtures(set, subset)
    raise "Cannot deploy empty template set" if fixtures.empty?

    yield fixtures if block_given?

    success = false
    Dir.mktmpdir("fixture_dir") do |target_dir|
      write_fixtures_to_dir(fixtures, target_dir)
      success = deploy_dirs(target_dir, args)
    end
    success
  end

  def deploy_global_fixtures(set, subset: nil, selector: nil, verify_result: true, prune: true, global_timeout: 300)
    fixtures = load_fixtures(set, subset)
    raise "Cannot deploy empty template set" if fixtures.empty?

    selector = (selector == false ? "" : "#{selector},app=krane,test=#{@namespace}".sub(/^,/, ''))
    apply_scope_to_resources(fixtures, labels: selector)

    yield fixtures if block_given?

    target_dir = Dir.mktmpdir("fixture_dir")
    write_fixtures_to_dir(fixtures, target_dir)
    @global_fixtures_deployed << target_dir

    deploy = Krane::GlobalDeployTask.new(
      context: KubeclientHelper::TEST_CONTEXT,
      filenames: Array(target_dir),
      global_timeout: global_timeout,
      selector: Krane::LabelSelector.parse(selector),
      logger: logger,
    )
    deploy.run(
      verify_result: verify_result,
      prune: prune
    )
  end

  def deploy_raw_fixtures(set, wait: true, bindings: {}, subset: nil, render_erb: false)
    success = false
    if subset
      Dir.mktmpdir("fixture_dir") do |target_dir|
        partials_dir = File.join(fixture_path(set), 'partials')
        if File.directory?(partials_dir)
          FileUtils.copy_entry(partials_dir, File.join(target_dir, 'partials'))
        end

        subset.each do |file|
          FileUtils.copy_entry(File.join(fixture_path(set), file), File.join(target_dir, file))
        end
        success = deploy_dirs(target_dir, wait: wait, bindings: bindings, render_erb: render_erb)
      end
    else
      success = deploy_dirs(fixture_path(set), wait: wait, bindings: bindings, render_erb: render_erb)
    end
    success
  end

  def deploy_dirs_without_profiling(dirs, wait: true, prune: true, bindings: {},
    sha: "k#{SecureRandom.hex(6)}", kubectl_instance: nil, global_timeout: nil, selector: nil,
    protected_namespaces: nil, render_erb: false)
    kubectl_instance ||= build_kubectl

    deploy = Krane::DeployTask.new(
      namespace: @namespace,
      current_sha: sha,
      context: KubeclientHelper::TEST_CONTEXT,
      filenames: dirs,
      logger: logger,
      kubectl_instance: kubectl_instance,
      bindings: bindings,
      global_timeout: global_timeout,
      selector: selector,
      protected_namespaces: protected_namespaces,
      render_erb: render_erb
    )
    deploy.run(
      verify_result: wait,
      prune: prune
    )
  end

  # Deploys all fixtures in the given directories via Krane::DeployTask
  # Exposed for direct use only when deploy_fixtures cannot be used because the template cannot be loaded pre-deploy,
  # for example because it contains an intentional syntax error
  def deploy_dirs(*dirs, **args)
    if ENV["PROFILE"]
      deploy_result = nil
      result = RubyProf.profile { deploy_result = deploy_dirs_without_profiling(dirs, args) }
      printer = RubyProf::FlameGraphPrinter.new(result)
      filename = File.expand_path("../../../dev/profile", __FILE__)
      printer.print(File.new(filename, "a+"), {})
      deploy_result
    else
      deploy_dirs_without_profiling(dirs, args)
    end
  end

  def setup_template_dir(set, subset: nil)
    fixtures = load_fixtures(set, subset)
    Dir.mktmpdir("fixture_dir") do |target_dir|
      write_fixtures_to_dir(fixtures, target_dir)
      yield target_dir if block_given?
    end
  end

  private

  def load_fixtures(set, subset)
    fixtures = {}
    if !subset || subset.include?("secrets.ejson")
      ejson_file = File.join(fixture_path(set), EJSON_FILENAME)
      fixtures[EJSON_FILENAME] = JSON.parse(File.read(ejson_file)) if File.exist?(ejson_file)
    end

    Dir.glob("#{fixture_path(set)}/*.{yml,yaml}*").each do |filename|
      basename = File.basename(filename)
      next unless !subset || subset.include?(basename)

      content = File.read(filename)
      fixtures[basename] = {}
      YAML.load_stream(content) do |doc|
        fixtures[basename][doc["kind"]] ||= []
        fixtures[basename][doc["kind"]] << doc
      end
    end
    fixtures
  end

  def write_fixtures_to_dir(fixtures, target_dir)
    fixtures.each do |filename, file_data|
      data_str = filename == EJSON_FILENAME ? file_data.to_json : YAML.dump_stream(*file_data.values.flatten)
      File.write(File.join(target_dir, filename), data_str)
    end
  end

  def build_kubectl(log_failure_by_default: true, timeout: '5s')
    Krane::Kubectl.new(task_config: task_config,
      log_failure_by_default: log_failure_by_default, default_timeout: timeout)
  end

  def add_unique_prefix_for_test(original_name)
    "t#{Digest::MD5.hexdigest(@namespace)}-#{original_name}"
  end

  def apply_scope_to_resources(fixtures, labels:)
    labels = Krane::LabelSelector.parse(labels).to_h
    fixtures.each do |_, kinds_map|
      kinds_map.each do |_, resources|
        resources.each do |resource|
          resource["metadata"]["labels"] = (resource.dig("metadata", "labels") || {}).merge(labels) if labels.present?
          if resource["kind"] == "CustomResourceDefinition"
            %w(kind listKind plural singular).each do |field|
              if (original_name = resource.dig("spec", "names", field))
                resource["spec"]["names"][field] = add_unique_prefix_for_test(original_name)
              end
            end
            # metadata.name has to be composed this way for CRDs
            resource["metadata"]["name"] = "#{resource['spec']['names']['plural']}.#{resource['spec']['group']}"
          else
            resource["metadata"]["name"] = add_unique_prefix_for_test(resource["metadata"]["name"])[0..63]
          end
        end
      end
    end
  end
end
