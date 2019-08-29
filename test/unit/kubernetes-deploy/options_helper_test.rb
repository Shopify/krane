# frozen_string_literal: true
require 'test_helper'
require 'tempfile'
require 'kubernetes-deploy/options_helper'

class OptionsHelperTest < KubernetesDeploy::TestCase
  include EnvTestHelper
  def test_with_template_dir
    KubernetesDeploy::OptionsHelper.with_validated_template_dir(fixture_path('hello-cloud')) do |template_dir|
      assert_equal(fixture_path('hello-cloud'), template_dir)
    end
  end

  def test_template_dir_with_default_env_var
    with_env("ENVIRONMENT", "test") do
      KubernetesDeploy::OptionsHelper.with_validated_template_dir(nil) do |template_dir|
        assert_equal(template_dir, File.join("config", "deploy", "test"))
      end
    end
  end

  def test_missing_template_dir_raises
    with_env("ENVIRONMENT", nil) do
      assert_raises(KubernetesDeploy::OptionsHelper::OptionsError) do
        KubernetesDeploy::OptionsHelper.with_validated_template_dir(nil) do
        end
      end
    end
  end

  def test_with_explicit_template_dir_with_env_var_set
    with_env("ENVIRONMENT", "test") do
      KubernetesDeploy::OptionsHelper.with_validated_template_dir(fixture_path('hello-cloud')) do |template_dir|
        assert_equal(fixture_path('hello-cloud'), template_dir)
      end
    end
  end

  def test_with_template_dir_from_stdin
    old_stdin = $stdin
    fixture_yamls = []
    stdin_yamls = []

    input = Tempfile.open("kubernetes_deploy_test")
    fixture_path_entries = Dir.glob("#{fixture_path('hello-cloud')}/*.{yml,yaml}*")
    fixture_path_entries.each do |filename|
      File.open(filename, 'r') do |f|
        contents = f.read
        input.print(contents + "\n---\n")
        contents.split(/^---$/).reject(&:empty?).each { |c| fixture_yamls << YAML.safe_load(c) }
      end
    end
    input.rewind
    $stdin = input

    KubernetesDeploy::OptionsHelper.with_validated_template_dir('-') do |template_dir|
      split_templates = File.read(
        File.join(template_dir, KubernetesDeploy::OptionsHelper::STDIN_TEMP_FILE)
      ).split(/^---$/).map(&:strip).reject(&:empty?)
      refute(split_templates.empty?)
      split_templates.each do |template|
        stdin_yamls << YAML.safe_load(template)
      end

      fixture_yamls.each do |fixture|
        assert(stdin_yamls.include?(fixture))
      end
    end
  ensure
    $stdin = old_stdin
  end
end
