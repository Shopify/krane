# frozen_string_literal: true
require 'test_helper'
require 'kubernetes-deploy/render_task'

class RenderTaskTest < KubernetesDeploy::TestCase
  include FixtureDeployHelper

  def test_render_task
    render = build_render_task(fixture_path('hello-cloud'))
    fixture = 'configmap-data.yml'

    assert_render_success(render.run(fixture, test_output_stream))

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

  def test_render_task_with_partials_and_bindings
    render = build_render_task(fixture_path('test-partials'), 'supports_partials': 'yep')
    fixture = 'deployment.yaml.erb'

    assert_render_success(render.run(fixture, test_output_stream))
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

  def test_render_invalid_binding
    render = build_render_task(fixture_path('test-partials'), 'a': 'binding-a', 'b': 'binding-b')
    fixture = 'deployment.yaml.erb'

    assert !render.run(fixture, test_output_stream)
    assert_logs_match_all([
      /Invalid template: deployment.yaml.erb/,
      /undefined local variable or method `supports_partials'/
    ])
  end

  def test_render_invalid_arguments
    render = build_render_task(fixture_path('test-partials'), 'a': 'binding-a')

    assert !render.run("", test_output_stream)
    assert_logs_match_all([
      /Template can't be blank/
    ])
  end

  def test_render_invalid_yaml
    render = build_render_task(fixture_path('invalid'))
    fixture = 'yaml-error.yml'

    assert !render.run(fixture, test_output_stream)
    assert_logs_match_all([
      /Invalid template: yaml-error.yml/,
      /mapping values are not allowed/
    ])
  end

  def test_render_valid_fixtures
    render = build_render_task(fixture_path('hello-cloud'))
    load_fixtures('hello-cloud', nil).each do |basename, _docs|
      assert_render_success(render.run(basename, test_output_stream))
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
end
