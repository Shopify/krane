# frozen_string_literal: true
require 'test_helper'
require 'krane/render_task'

class RenderTaskTest < Krane::TestCase
  include FixtureDeployHelper

  def test_render_task
    render = build_render_task(
      File.join(fixture_path('hello-cloud'), 'configmap-data.yml')
    )

    assert_render_success(render.run(mock_output_stream))

    stdout_assertion do |output|
      assert_equal output, <<~RENDERED
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: hello-cloud-configmap-data
          labels:
            name: hello-cloud-configmap-data
            app: hello-cloud
        data:
          datapoint1: value1
          datapoint2: value2
      RENDERED
    end
  end

  def test_render_task_multiple_templates
    SecureRandom.expects(:hex).with(4).returns('aaaa')
    SecureRandom.expects(:hex).with(6).returns('bbbbbb')
    render = build_render_task([
      File.join(fixture_path('hello-cloud'), 'configmap-data.yml'),
      File.join(fixture_path('hello-cloud'), 'unmanaged-pod-1.yml.erb'),
    ])
    assert_render_success(render.run(mock_output_stream))

    stdout_assertion do |output|
      expected = <<~RENDERED
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: hello-cloud-configmap-data
          labels:
            name: hello-cloud-configmap-data
            app: hello-cloud
        data:
          datapoint1: value1
          datapoint2: value2
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: unmanaged-pod-1-kbbbbbb-aaaa
          annotations:
            krane.shopify.io/timeout-override: 60s
          labels:
            type: unmanaged-pod
            name: unmanaged-pod-1-kbbbbbb-aaaa
            app: hello-cloud
        spec:
          activeDeadlineSeconds: 60
          restartPolicy: Never
          containers:
            - name: hello-cloud
              image: busybox
              imagePullPolicy: IfNotPresent
              command: ["sh", "-c", "echo 'Hello from the command runner!' && test 1 -eq 1"]
              env:
              - name: CONFIG
                valueFrom:
                  configMapKeyRef:
                    name: hello-cloud-configmap-data
                    key: datapoint2
      RENDERED
      assert_equal expected, output
    end
  end

  def test_render_task_with_partials_and_bindings
    render = build_render_task(
      File.join(fixture_path('test-partials'), 'deployment.yaml.erb'),
      'supports_partials': 'yep'
    )

    assert_render_success(render.run(mock_output_stream))
    stdout_assertion do |output|
      expected = <<~RENDERED
        ---
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: web
          labels:
            name: web
            app: test-partials
        spec:
          replicas: 1
          selector:
            matchLabels:
              name: web
              app: test-partials
          template:
            metadata:
              labels:
                name: web
                app: test-partials
            spec: {"containers":[{"name":"sleepy-guy","image":"busybox","imagePullPolicy":"IfNotPresent","command":["sleep","8000"]}]}
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: pod1
        spec:
          restartPolicy: "Never"
          activeDeadlineSeconds: 60
          containers:
          - name: pod1
            image: busybox
            args: ["echo", "log from pod1"]
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: config-for-pod1
        data:
          supports_partials: "yep"

        # This is valid
        ---						# leave this whitespace
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: independent-configmap
        data:
          value: "renderer test"

        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: pod2
        spec:
          restartPolicy: "Never"
          activeDeadlineSeconds: 60
          containers:
          - name: pod2
            image: busybox
            args: ["echo", "log from pod2"]
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: config-for-pod2
        data:
          supports_partials: "yep"

      RENDERED
      assert_equal expected, output
    end
  end

  def test_render_task_rendering_all_files
    render = build_render_task(fixture_path('hello-cloud'))

    assert_render_success(render.run(mock_output_stream))
    stdout_assertion do |output|
      assert_match(/name: bare-replica-set/, output)
      assert_match(/name: hello-cloud-configmap-data/, output)
      assert_match(/name: ds-app/, output)
      assert_match(/kind: PodDisruptionBudget/, output)
      assert_match(/name: hello-job/, output)
      assert_match(/name: redis/, output)
      assert_match(/name: role-binding/, output)
      assert_match(/name: resource-quotas/, output)
      assert_match(/name: allow-all-network-policy/, output)
      assert_match(/name: build-robot/, output)
      assert_match(/name: stateful-busybox/, output)
      assert_match(/name: hello-cloud-template-runner/, output)
      assert_match(/name: unmanaged-pod-\w+/, output)
      assert_match(/name: web/, output)
    end
  end

  def test_render_task_multiple_templates_with_middle_failure
    render = build_render_task([
      File.join(fixture_path('some-invalid'), 'configmap-data.yml'),
      File.join(fixture_path('some-invalid'), 'yaml-error.yml'),
      File.join(fixture_path('some-invalid'), 'stateful_set.yml'),
    ])
    assert_render_failure(render.run(mock_output_stream))

    stdout_assertion do |output|
      assert_match(/name: hello-cloud-configmap-data/, output)
      assert_match(/name: stateful-busybox/, output)
    end

    logging_assertion do |logs|
      assert_match(/Invalid template: yaml-error.yml/, logs)
    end
  end

  def test_render_invalid_binding
    render = build_render_task(
      File.join(fixture_path('test-partials'), 'deployment.yaml.erb'),
      'a': 'binding-a',
      'b': 'binding-b'
    )
    assert_render_failure(render.run(mock_output_stream))
    assert_logs_match_all([
      /Invalid template: .*deployment.yaml.erb/,
      "> Error message:",
      /undefined local variable or method `supports_partials'/,
      "> Template content:",
      'supports_partials: "<%= supports_partials %>"',
    ], in_order: true)
  end

  def test_render_runtime_error_when_rendering
    render = build_render_task(
      File.join(fixture_path('invalid'), 'raise_inside.yml.erb')
    )
    assert_render_failure(render.run(mock_output_stream))
    assert_logs_match_all([
      /Invalid template: .*raise_inside.yml.erb/,
      "> Error message:",
      /mock error when evaluating erb/,
      "> Template content:",
      'datapoint1: <% raise RuntimeError, "mock error when evaluating erb" %>',
    ], in_order: true)
  end

  def test_render_empty_template_dir
    tmp_dir = Dir.mktmpdir
    render = build_render_task(tmp_dir)
    assert_render_failure(render.run(mock_output_stream))
    assert_logs_match_all([
      "Template directory #{tmp_dir} does not contain any valid templates",
    ])
  end

  def test_render_invalid_yaml
    render = build_render_task(
      File.join(fixture_path('invalid'), 'yaml-error.yml'),
      data: "data"
    )
    assert_render_failure(render.run(mock_output_stream))
    assert_logs_match_all([
      /Invalid template: .*yaml-error.yml/,
      "> Error message:",
      /mapping values are not allowed/,
    ], in_order: true)
  end

  def test_render_valid_fixtures
    load_fixtures('hello-cloud', nil).each do |basename, _docs|
      render = build_render_task(
        File.join(fixture_path('hello-cloud'), basename)
      )
      assert_render_success render.run(mock_output_stream)
      stdout_assertion do |output|
        assert !output.empty?
      end
    end
  end

  def test_render_only_adds_initial_doc_separator_when_missing
    render = build_render_task([
      File.join(fixture_path('partials'), 'no-doc-separator.yml.erb'),
      File.join(fixture_path('partials'), 'no-doc-separator.yml.erb'),
    ])
    expected = "---\n# The first doc has no yaml separator\nkey1: foo\n---\nkey2: bar\n"

    assert_render_success(render.run(mock_output_stream))
    stdout_assertion do |output|
      assert_equal "#{expected}#{expected}", output
    end

    mock_output_stream.rewind
    render = build_render_task(
      File.join(fixture_path('test-partials/partials'), 'independent-configmap.yml.erb'),
      data: "data"
    )
    expected = <<~RENDERED
      # This is valid
      ---						# leave this whitespace
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: independent-configmap
      data:
        value: "data"
      RENDERED

    assert_render_success(render.run(mock_output_stream))
    stdout_assertion do |output|
      assert_equal expected, output
    end
  end

  def test_render_preserves_duplicate_keys
    render = build_render_task(
      File.join(fixture_path('partials'), 'duplicate-keys.yml.erb')
    )
    expected = "---\nkey1: \"0\"\nkey1: \"1\"\nkey1: \"2\"\n"

    assert_render_success(render.run(mock_output_stream))
    stdout_assertion do |output|
      assert_equal expected, output
    end
  end

  def test_render_does_not_generate_extra_blank_documents_when_file_is_empty
    render = build_render_task(
      File.join(fixture_path('collection-with-erb'), 'effectively_empty.yml.erb')
    )
    assert_render_success(render.run(mock_output_stream))
    stdout_assertion do |output|
      assert_equal "", output.strip
    end
    assert_logs_match("Rendered effectively_empty.yml.erb successfully, but the result was blank")
  end

  private

  def build_render_task(filenames, bindings = {})
    Krane::RenderTask.new(
      logger: logger,
      current_sha: "k#{SecureRandom.hex(6)}",
      bindings: bindings,
      filenames: Array(filenames)
    )
  end

  def assert_render_success(result)
    assert_equal(true, result, "Render failed when it was expected to succeed.#{logs_message_if_captured}")
    logging_assertion do |logs|
      assert_match Regexp.new("Result: SUCCESS"), logs, "'Result: SUCCESS' not found in the following logs:\n#{logs}"
    end
  end

  def assert_render_failure(result)
    assert_equal(false, result, "Render succeeded when it was expected to fail.#{logs_message_if_captured}")
    logging_assertion do |logs|
      assert_match Regexp.new("Result: FAILURE"), logs, "'Result: FAILURE' not found in the following logs:\n#{logs}"
    end
  end
end
