# frozen_string_literal: true
require 'securerandom'
module FixtureDeployHelper
  EJSON_FILENAME = KubernetesDeploy::EjsonSecretProvisioner::EJSON_SECRETS_FILE

  # Deploys the specified set of fixtures via KubernetesDeploy::DeployTask.
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

  def deploy_raw_fixtures(set, wait: true, bindings: {}, subset: nil)
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
        success = deploy_dirs(target_dir, wait: wait, bindings: bindings)
      end
    else
      success = deploy_dirs(fixture_path(set), wait: wait, bindings: bindings)
    end
    success
  end

  def deploy_dirs_without_profiling(dirs, wait: true, allow_protected_ns: false, prune: true, bindings: {},
    sha: "k#{SecureRandom.hex(6)}", kubectl_instance: nil, max_watch_seconds: nil, selector: nil)
    kubectl_instance ||= build_kubectl

    deploy = KubernetesDeploy::DeployTask.new(
      namespace: @namespace,
      current_sha: sha,
      context: KubeclientHelper::TEST_CONTEXT,
      template_paths: dirs,
      logger: logger,
      kubectl_instance: kubectl_instance,
      bindings: bindings,
      max_watch_seconds: max_watch_seconds,
      selector: selector,
    )
    deploy.run(
      verify_result: wait,
      allow_protected_ns: allow_protected_ns,
      prune: prune
    )
  end

  # Deploys all fixtures in the given directories via KubernetesDeploy::DeployTask
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
    KubernetesDeploy::Kubectl.new(namespace: @namespace, context: KubeclientHelper::TEST_CONTEXT, logger: logger,
      log_failure_by_default: log_failure_by_default, default_timeout: timeout)
  end
end
