# frozen_string_literal: true
module FixtureDeployHelper
  # Deploys the specified set of fixtures via KubernetesDeploy::Runner.
  #
  # Optionally takes an array of filenames belonging to the fixture, and deploys that subset only.
  # Example:
  # # Deploys basic/redis.yml
  # deploy_fixtures("basic", ["redis.yml"])
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
  # # The following will deploy the "basic" fixture set, but with the unmanaged pod modified to use a bad image
  #   deploy_fixtures("basic") do |fixtures|
  #     pod = fixtures["unmanaged-pod.yml.erb"]["Pod"].first
  #     pod["spec"]["containers"].first["image"] = "hello-world:thisImageIsBad"
  #   end
  def deploy_fixtures(set, subset: nil, wait: true)
    fixtures = load_fixtures(set, subset)
    raise "Cannot deploy empty template set" if fixtures.empty?

    yield fixtures if block_given?

    target_dir = Dir.mktmpdir
    write_fixtures_to_dir(fixtures, target_dir)
    deploy_dir(target_dir, wait: wait)
  ensure
    FileUtils.remove_dir(target_dir) if target_dir
  end

  def deploy_raw_fixtures(set, wait: true)
    deploy_dir(fixture_path(set), wait: wait)
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
  def deploy_dir(dir, sha: 'abcabcabc', wait: true)
    runner = KubernetesDeploy::Runner.new(
      namespace: @namespace,
      current_sha: sha,
      context: KubeclientHelper::MINIKUBE_CONTEXT,
      template_dir: dir,
      wait_for_completion: wait,
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
