# frozen_string_literal: true
require 'test_helper'
require 'kubernetes-deploy/render_task'

class RenderTaskTest < KubernetesDeploy::TestCase
  include FixtureDeployHelper

  def test_render_task
    render = build_render_task(fixture_path('hello-cloud'))
    fixture = 'configmap-data.yml'

    assert_render_success render.run(mock_output_stream, [fixture])

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
    render = build_render_task(fixture_path('hello-cloud'))
    assert_render_success render.run(mock_output_stream, ['configmap-data.yml', 'unmanaged-pod.yml.erb'])

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
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: unmanaged-pod-kbbbbbb-aaaa
          annotations:
            kubernetes-deploy.shopify.io/timeout-override: 60s
          labels:
            type: unmanaged-pod
            name: unmanaged-pod-kbbbbbb-aaaa
            app: hello-cloud
        spec:
          activeDeadlineSeconds: 60
          restartPolicy: Never
          containers:
          - name: hello-cloud
            image: busybox
            imagePullPolicy: IfNotPresent
            command:
            - sh
            - "-c"
            - echo 'Hello from the command runner!' && test 1 -eq 1
            env:
            - name: CONFIG
              valueFrom:
                configMapKeyRef:
                  name: hello-cloud-configmap-data
                  key: datapoint2
      RENDERED
    end
  end

  def test_render_task_with_partials_and_bindings
    render = build_render_task(fixture_path('test-partials'), 'supports_partials': 'yep')
    fixture = 'deployment.yaml.erb'

    assert_render_success render.run(mock_output_stream, [fixture])
    stdout_assertion do |output|
      assert_equal output, <<~RENDERED
        ---
        apiVersion: extensions/v1beta1
        kind: Deployment
        metadata:
          name: web
        spec:
          replicas: 1
          template:
            metadata:
              labels:
                name: web
                app: test-partials
            spec:
              containers:
              - name: sleepy-guy
                image: busybox
                imagePullPolicy: IfNotPresent
                command:
                - sleep
                - '8000'
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: pod1
        spec:
          restartPolicy: Never
          activeDeadlineSeconds: 60
          containers:
          - name: pod1
            image: busybox
            args:
            - echo
            - log from pod1
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: config-for-pod1
        data:
          supports_partials: yep
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: independent-configmap
        data:
          value: renderer test
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: pod2
        spec:
          restartPolicy: Never
          activeDeadlineSeconds: 60
          containers:
          - name: pod2
            image: busybox
            args:
            - echo
            - log from pod2
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: config-for-pod2
        data:
          supports_partials: yep
      RENDERED
    end
  end

  def test_render_task_rendering_all_files
    render = build_render_task(fixture_path('hello-cloud'))

    assert_render_success render.run(mock_output_stream, [])
    stdout_assertion do |output|
      assert_match(/name: bare-replica-set/, output)
      assert_match(/name: hello-cloud-configmap-data/, output)
      assert_match(/name: ds-app/, output)
      assert_match(/kind: PodDisruptionBudget/, output)
      assert_match(/name: hello-job/, output)
      assert_match(/name: redis/, output)
      assert_match(/name: role-binding/, output)
      assert_match(/name: resource-quotas/, output)
      assert_match(/name: build-robot/, output)
      assert_match(/name: stateful-busybox/, output)
      assert_match(/name: hello-cloud-template-runner/, output)
      assert_match(/name: unmanaged-pod-\w+/, output)
      assert_match(/name: web/, output)
    end
  end

  def test_render_invalid_binding
    render = build_render_task(fixture_path('test-partials'), 'a': 'binding-a', 'b': 'binding-b')
    fixture = 'deployment.yaml.erb'

    assert_render_failure render.run(mock_output_stream, [fixture])
    assert_logs_match_all([
      /Invalid template: .*deployment.yaml.erb/,
      /undefined local variable or method `supports_partials'/
    ])
  end

  def test_render_invalid_arguments
    render = build_render_task(fixture_path('test-partials'), 'a': 'binding-a')

    assert_render_failure render.run(mock_output_stream, ["../"])
    assert_logs_match_all([
      %r{test/fixtures" is not a file}
    ])
  end

  def test_render_path_outside_template_dir
    render = build_render_task(fixture_path('test-partials'), 'a': 'binding-a')

    assert_render_failure render.run(mock_output_stream, ["../hello-cloud/configmap-data.yml"])
    assert_logs_match_all([
      %r{test/fixtures/hello-cloud/configmap-data.yml" is outside the template dir}
    ])
  end

  def test_render_empty_template_dir
    render = build_render_task(Dir.mktmpdir)

    assert_render_failure render.run(mock_output_stream)
    assert_logs_match_all([
      /no templates found in template dir/
    ])
  end

  def test_render_invalid_yaml
    render = build_render_task(fixture_path('invalid'))
    fixture = 'yaml-error.yml'

    assert_render_failure render.run(mock_output_stream, [fixture])
    assert_logs_match_all([
      /Invalid template: .*yaml-error.yml/,
      /mapping values are not allowed/
    ])
  end

  def test_render_valid_fixtures
    render = build_render_task(fixture_path('hello-cloud'))
    load_fixtures('hello-cloud', nil).each do |basename, _docs|
      assert_render_success render.run(mock_output_stream, [basename])
      stdout_assertion do |output|
        assert !output.empty?
      end
    end
  end

  private

  def build_render_task(template_dir, bindings = {})
    KubernetesDeploy::RenderTask.new(
      logger: logger,
      current_sha: "k#{SecureRandom.hex(6)}",
      bindings: bindings,
      template_dir: template_dir
    )
  end

  def assert_render_success(result)
    assert_equal true, result, "Render failed when it was expected to succeed.#{logs_message_if_captured}"
    logging_assertion do |logs|
      assert_match Regexp.new("Result: SUCCESS"), logs, "'Result: SUCCESS' not found in the following logs:\n#{logs}"
    end
  end

  def assert_render_failure(result)
    assert_equal false, result, "Render succeeded when it was expected to fail.#{logs_message_if_captured}"
    logging_assertion do |logs|
      assert_match Regexp.new("Result: FAILURE"), logs, "'Result: FAILURE' not found in the following logs:\n#{logs}"
    end
  end
end
