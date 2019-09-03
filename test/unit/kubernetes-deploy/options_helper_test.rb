# frozen_string_literal: true
require 'test_helper'
require 'tempfile'
require 'kubernetes-deploy/options_helper'

class OptionsHelperTest < KubernetesDeploy::TestCase
  include EnvTestHelper
  def test_with_template_dir
    KubernetesDeploy::OptionsHelper.with_processed_template_paths([fixture_path('hello-cloud')]) do |template_paths|
      assert_equal(template_paths, [fixture_path('hello-cloud')])
    end
  end

  def test_template_dir_with_default_env_var
    with_env("ENVIRONMENT", "test") do
      assert_raises_message(KubernetesDeploy::OptionsHelper::OptionsError,
        "Template directory config/deploy/test does not exist") do
        KubernetesDeploy::OptionsHelper.with_processed_template_paths([])
      end
    end
  end

  def test_missing_template_dir_raises
    with_env("ENVIRONMENT", nil) do
      assert_raises_message(KubernetesDeploy::OptionsHelper::OptionsError,
        "Template directory is unknown. " \
        "Either specify --template-dir argument or set $ENVIRONMENT to use config/deploy/$ENVIRONMENT " \
        "as a default path.") do
        KubernetesDeploy::OptionsHelper.with_processed_template_paths([]) do
        end
      end
    end
  end

  def test_with_explicit_template_dir_with_env_var_set
    with_env("ENVIRONMENT", "test") do
      KubernetesDeploy::OptionsHelper.with_processed_template_paths([fixture_path('hello-cloud')]) do |template_paths|
        assert_equal(template_paths, [fixture_path('hello-cloud')])
      end
    end
  end

  def test_with_multiple_template_paths
    KubernetesDeploy::OptionsHelper.with_processed_template_paths(
      [fixture_path('hello-cloud'), fixture_path('cronjobs')]
    ) do |template_paths|
      assert_equal(template_paths, [fixture_path('hello-cloud'), fixture_path('cronjobs')])
    end
  end

  def test_with_multiple_template_paths_with_stdin
    wrapped_stdin do |input|
      fixture_yamls = []
      stdin_yamls = []
      fixture_yamls = fixtures_for_stdin(fixture_path: fixture_path("hello-cloud"), file: input)

      KubernetesDeploy::OptionsHelper.with_processed_template_paths(['-', 'cronjobs']) do |template_paths|
        stdin_dir = (template_paths - ['cronjobs']).first
        split_templates = File.read(
          File.join(stdin_dir, KubernetesDeploy::OptionsHelper::STDIN_TEMP_FILE)
        ).split(/^---$/).map(&:strip).reject(&:empty?)
        refute(split_templates.empty?)
        split_templates.each do |template|
          stdin_yamls << YAML.safe_load(template)
        end
        fixture_yamls.each do |fixture|
          assert(stdin_yamls.include?(fixture))
        end
        assert(template_paths.include?('cronjobs'))
      end
    end
  end

  def test_with_template_dir_from_stdin
    wrapped_stdin do |input|
      fixture_yamls = []
      stdin_yamls = []
      fixture_yamls = fixtures_for_stdin(fixture_path: fixture_path("hello-cloud"), file: input)

      KubernetesDeploy::OptionsHelper.with_processed_template_paths(['-']) do |template_paths|
        split_templates = File.read(
          File.join(template_paths.first, KubernetesDeploy::OptionsHelper::STDIN_TEMP_FILE)
        ).split(/^---$/).map(&:strip).reject(&:empty?)
        refute(split_templates.empty?)
        split_templates.each do |template|
          stdin_yamls << YAML.safe_load(template)
        end

        fixture_yamls.each do |fixture|
          assert(stdin_yamls.include?(fixture))
        end
      end
    end
  end

  def test_with_repeated_template_paths
    wrapped_stdin do
      KubernetesDeploy::OptionsHelper.with_processed_template_paths(['-', '-']) do |template_paths|
        assert_equal(template_paths.length, 1)
      end
    end

    KubernetesDeploy::OptionsHelper.with_processed_template_paths(
      [fixture_path('hello-cloud'), fixture_path('hello-cloud')]
    ) do |template_paths|
      assert_equal(template_paths.length, 1)
    end
  end

  private

  def fixtures_for_stdin(fixture_path:, file:)
    fixture_yamls = []
    fixture_path_entries = Dir.glob("#{fixture_path}/*.{yml,yaml}*")
    fixture_path_entries.each_with_object(fixture_yamls) do |filename, fixtures|
      File.open(filename, 'r') do |f|
        contents = f.read
        file.print(contents + "\n---\n")
        contents.split(/^---$/).reject(&:empty?).each { |c| fixtures << YAML.safe_load(c) }
      end
    end
    file.rewind
    fixture_yamls
  end

  def wrapped_stdin
    old_stdin = $stdin
    input = Tempfile.open("kubernetes_deploy_test")
    $stdin = input
    yield input
  ensure
    $stdin = old_stdin
    input.close
    input.unlink
  end
end
