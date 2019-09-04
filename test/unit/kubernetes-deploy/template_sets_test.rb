# frozen_string_literal: true

require 'test_helper'

class TemplateSetsTest < KubernetesDeploy::TestCase
  def test_valid_template_sets_is_valid
    template_paths = [
      fixture_path("hello-cloud"),
      File.join(fixture_path("ejson-cloud"), "secrets.ejson"),
    ]
    template_sets = template_sets_from_paths(*template_paths)
    assert_predicate(template_sets.validate, :empty?)
  end

  def test_empty_template_sets_directory_is_invalid
    Dir.mktmpdir("empty_dir") do |dir|
      template_sets = template_sets_from_paths(dir)
      expected = [
        "Template directory #{dir} does not contain any valid templates",
      ]
      assert_equal(template_sets.validate, expected)
    end
  end

  def test_template_sets_with_invalid_suffix_is_invalid
    bad_filepath = File.join(fixture_path("for_unit_tests"), "bindings.json")
    template_sets = template_sets_from_paths(bad_filepath)
    expected = [
      "File #{bad_filepath} does not have valid suffix (supported suffixes: " \
        ".yml.erb, .yml, .yaml, .yaml.erb, or secrets.ejson)",
    ]
    assert_equal(template_sets.validate, expected)
  end

  def test_template_sets_with_non_existent_file_is_invalid
    file_not_exists = File.join(fixture_path("hello-cloud"), "doesnt_exist.yml")
    template_sets = template_sets_from_paths(file_not_exists)
    expected = [
      "File #{file_not_exists} does not exist",
    ]
    assert_equal(template_sets.validate, expected)
  end

  private

  def template_sets_from_paths(*paths)
    KubernetesDeploy::TemplateSets.from_dirs_and_files(
      paths: paths,
      logger: logger
    )
  end
end
