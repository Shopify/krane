# frozen_string_literal: true
require 'securerandom'
module FixtureDeployHelper
  # Deploys the specified set of fixtures via KubernetesDeploy::Runner.
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
  def deploy_fixtures(set, subset: nil, wait: true, allow_protected_ns: false, prune: true, bindings: {})
    fixtures = load_fixtures(set, subset)
    raise "Cannot deploy empty template set" if fixtures.empty?

    yield fixtures if block_given?

    target_dir = Dir.mktmpdir
    write_fixtures_to_dir(fixtures, target_dir)
    deploy_dir(target_dir, wait: wait, allow_protected_ns: allow_protected_ns, prune: prune, bindings: bindings)
  ensure
    FileUtils.remove_dir(target_dir) if target_dir
  end

  def deploy_raw_fixtures(set, wait: true, bindings: {})
    deploy_dir(fixture_path(set), wait: wait, bindings: bindings)
  end

  def fixture_path(set_name)
    source_dir = File.expand_path("../../fixtures/#{set_name}", __FILE__)
    raise ArgumentError,
      "Fixture set #{set_name} does not exist as directory #{source_dir}" unless File.directory?(source_dir)
    source_dir
  end

  # Deploys all fixtures in the given directory via KubernetesDeploy::Runner
  # Exposed for direct use only when deploy_fixtures cannot be used because the template cannot be loaded pre-deploy,
  # for example because it contains an intentional syntax error
  def deploy_dir(dir, wait: true, allow_protected_ns: false, prune: true, bindings: {})
    runner = KubernetesDeploy::Runner.new(
      namespace: @namespace,
      current_sha: SecureRandom.hex(6),
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      template_dir: dir,
      wait_for_completion: wait,
      allow_protected_ns: allow_protected_ns,
      prune: prune,
      bindings: bindings
    )
    runner.run
  end

  private

  def load_fixtures(set, subset)
    fixtures = {}
    Dir["#{fixture_path(set)}/*.yml*"].each do |filename|
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
    files = [] # keep reference outside Tempfile.open to prevent garbage collection
    fixtures.each do |filename, file_data|
      basename, exts = extract_basename_and_extensions(filename)
      data = YAML.dump_stream(*file_data.values.flatten)
      Tempfile.open([basename, exts], target_dir) do |f|
        files << f
        f.write(data)
      end
    end
  end

  def extract_basename_and_extensions(filename)
    match_data = filename.match(/(?<basename>.*)(?<ext>\.yml(?:\.erb)?)\z/)
    [match_data[:basename], match_data[:ext]]
  end
end
