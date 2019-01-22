# frozen_string_literal: true
require 'test_helper'
require 'tempfile'

class OptionsHelperTest < KubernetesDeploy::TestCase
  def test_single_template_dir_only
    KubernetesDeploy::OptionsHelper.with_consolidated_template_dir([fixture_path('hello-cloud')]) do |template_dir|
      assert_equal(fixture_path('hello-cloud'), template_dir)
    end
  end

  def test_multiple_template_dirs
    template_dirs = [fixture_path('hello-cloud'), fixture_path('partials')]

    KubernetesDeploy::OptionsHelper.with_consolidated_template_dir(template_dirs) do |template_dir|
      fixture_path_entries = template_dirs.collect { |dir| Dir.entries(dir) }.flatten.uniq
      template_dir_entries = Dir.entries(template_dir)
      assert_equal(fixture_path_entries.length, template_dir_entries.length)
      fixture_path_entries.each do |fixture|
        assert(template_dir_entries.select { |s| s.include?(fixture) })
      end
    end
  end

  def test_missing_template_dir_raises
    assert_raises(KubernetesDeploy::OptionsHelper::OptionsError) do
      KubernetesDeploy::OptionsHelper.with_consolidated_template_dir([]) do
      end
    end
  end

  def test_template_dir_with_stdin
    old_stdin = $stdin

    input = Tempfile.open("kubernetes_deploy_test")
    File.open("#{fixture_path('for_unit_tests')}/service_test.yml", 'r') do |f|
      input.print(f.read)
    end
    input.rewind
    $stdin = input

    KubernetesDeploy::OptionsHelper.with_consolidated_template_dir([fixture_path('hello-cloud'), '-']) do |template_dir|
      assert_equal(
        File.read(File.join(template_dir, KubernetesDeploy::OptionsHelper::STDIN_TEMP_FILE)),
        File.read(File.join(fixture_path('for_unit_tests'), 'service_test.yml'))
      )

      fixture_path_yamls = []
      fixture_path_entries = Dir.glob("#{fixture_path('hello-cloud')}/*.{yml,yaml}*")
      fixture_path_entries.each do |path|
        File.read(path).split(/^---$/).reject(&:empty?).each do |f|
          fixture_path_yamls << YAML.safe_load(f)
        end
      end

      template_dir_yamls = []
      template_dir_entries = Dir.glob("#{template_dir}/*").reject { |f| f.include?("from_stdin.yml.erb") }
      template_dir_entries.each do |path|
        File.read(path).split(/^---$/).reject(&:empty?).each do |f|
          template_dir_yamls << YAML.safe_load(f)
        end
      end
      fixture_path_yamls.each do |fixture|
        assert(template_dir_yamls.include?(fixture))
      end
    end
  ensure
    $stdin = old_stdin
  end

  def test_only_stdin_template_dir
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

    KubernetesDeploy::OptionsHelper.with_consolidated_template_dir(['-']) do |template_dir|
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
