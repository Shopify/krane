module FixtureDeployHelper
  # Deploys the templates in the specified fixture set via KubernetesDeploy::Runner.
  # Optionally takes an array of names of template files in that set, in which case only those files are deployed.
  # If you need to add to or modify the fixture set before deploying,
  # use load_fixture_data(set, subset=nil) and deploy_loaded_fixture_set(template_map, wait: true) instead.
  def deploy_fixture_set(set, subset: nil, wait: true)
    source_dir = fixture_path(set)
    return deploy_dir(source_dir) unless subset

    target_dir = Dir.mktmpdir
    files = []
    each_k8s_yaml(source_dir, subset) do |basename, ext, content|
      Tempfile.open([basename, ext], target_dir) do |f|
        files << f
        f.write(content)
      end
    end

    deploy_dir(target_dir, wait: wait)
  ensure
    FileUtils.remove_dir(target_dir) if target_dir
  end

  # Takes an array of templates in the format returned by load_fixture_data, saves them to a temporary directory,
  # and invokes KubernetesDeploy::Runner on that directory with the requested options.
  # Use this with load_fixture_data when you want to add to and/or modify the template set before deploying it.
  def deploy_loaded_fixture_set(template_map, wait: true)
    dir = Dir.mktmpdir
    files = []
    template_map.each do |file_basename, file_data|
      data = YAML.dump_stream(*file_data.values.flatten)
      # assume they're all erb now in case erb was added
      Tempfile.open([file_basename, ".yml.erb"], dir) do |f|
        files << f
        f.write(data)
      end
    end
    deploy_dir(dir, wait: wait)
  ensure
    files.each { |f| File.delete(f) }
  end

  # Returns a hash containing a key for each template file in the set.
  # The values of those keys are hashes containing a key for each resource type in the template file.
  # In turn, the values of those keys are arrays of loaded kubernetes resource yaml.
  #
  # Example:
  #   load_fixture_data("basic", ["web"])
  #   => {
  #        "web" => {
  #          "Ingress" => [loaded_ingress_yaml],
  #          "Service" => [loaded_service_yaml],
  #          "Deployment" => [loaded_service_yaml]
  #        }
  #      }
  def load_fixture_data(set, subset=nil)
    source_dir = fixture_path(set)
    templates = {}

    each_k8s_yaml(source_dir, subset) do |basename, ext, content|
      templates[basename] = {}
      YAML.load_stream(content) do |doc|
        templates[basename][doc["kind"]] ||= []
        templates[basename][doc["kind"]] << doc
      end
    end
    templates
  end

  private

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

  def fixture_path(set_name)
    source_dir = File.expand_path("../../fixtures/#{set_name}", __FILE__)
    raise "Fixture set pat #{source_dir} is invalid" unless File.directory?(source_dir)
    source_dir
  end

  def each_k8s_yaml(source_dir, subset)
    Dir["#{source_dir}/*.yml*"].each do |filename|
      match_data = File.basename(filename).match(/(?<basename>.*)(?<ext>\.yml(?:\.erb)?)\z/)
      basename = match_data[:basename]
      ext = match_data[:ext]
      next unless !subset || subset.include?(basename)

      yield basename, ext, File.read(filename)
    end
  end
end
