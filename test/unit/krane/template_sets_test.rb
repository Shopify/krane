# frozen_string_literal: true

require 'test_helper'

class TemplateSetsTest < Krane::TestCase
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
        "Template directory #{dir} does not contain any valid templates " \
          "(supported suffixes: .yml.erb, .yml, .yaml, .yaml.erb, or secrets.ejson)",
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

  def test_template_sets_with_erb_files_are_considered_invalid_when_render_erb_is_false
    bad_filepath = File.join(fixture_path("for_unit_tests"), "partials_test.yaml.erb")
    template_sets = template_sets_from_paths(bad_filepath, render_erb: false)
    expected = [
      "File #{bad_filepath} does not have valid suffix (supported suffixes: .yml, .yaml, or secrets.ejson)",
      "ERB template discovered with rendering disabled. If you were trying to render ERB and " \
        "deploy the result, try piping the output of `krane render` to `krane-deploy -f -`",
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

  def test_with_resource_definitions_and_filename_raw
    path = File.join(fixture_path("hello-cloud"), "rq.yml")
    template_sets = template_sets_from_paths(path)

    template_sets.with_resource_definitions_and_filename(raw: true) do |rendered, _|
      assert_match('kind: ResourceQuota', rendered)
    end
  end

  def test_with_resource_definitions_and_filename_delays_errors
    # Ordered so that failure is first
    paths = [File.join(fixture_path("test-partials/partials"), "independent-configmap.yml.erb"),
             File.join(fixture_path("hello-cloud"), "rq.yml")]
    template_sets = template_sets_from_paths(*paths)

    file_names = []
    template_sets.with_resource_definitions_and_filename(bindings: { data: "1" }) do |rendered_content, filename|
      file_names << filename
      refute_empty(rendered_content)
    end
    assert_equal(paths.map { |f| File.basename(f) }.sort, file_names.sort)

    file_names = []
    assert_raises(Krane::InvalidTemplateError) do
      template_sets.with_resource_definitions_and_filename(bindings: {}) do |rendered_content, filename|
        file_names << filename
        refute_empty(rendered_content)
      end
    end
    assert_equal(file_names.count, 1)
  end

  private

  def template_sets_from_paths(*paths, render_erb: true)
    Krane::TemplateSets.from_dirs_and_files(
      paths: paths,
      logger: logger,
      render_erb: render_erb
    )
  end
end
