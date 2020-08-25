# frozen_string_literal: true
require 'test_helper'

class RendererTest < Krane::TestCase
  def setup
    super
    SecureRandom.stubs(:hex).returns("aaaa")
    @renderer = Krane::Renderer.new(
      current_sha: "12345678",
      template_dir: fixture_path('for_unit_tests'),
      logger: logger,
      bindings: { "a" => "1", "b" => "2" }
    )
  end

  def test_can_render_template_with_correct_indentation
    expected = <<~EOY
      ---
      a: 1
      b: 2
      ---
      c: c3
      d: d4
      foo: bar
      ---
      e: e5
      f: f6
      ---
      foo: baz
      ---
      value: 4
      step:
        value: 3
        step:
          value: 2
          step:
            value: 1
            result: 24
      EOY
    actual = YAML.load_stream(render("partials_test.yaml.erb")).map do |t|
      YAML.dump_k8s_compatible(t)
    end.join
    assert_equal(expected, actual)
  end

  def test_renders_env_with_e_notation_correctly
    expected = <<~EOY
      ---
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: web
        annotations:
          shipit.shopify.io/restart: 'true'
        labels:
          name: web
          app: hello-cloud
      spec:
        replicas: 1
        selector:
          matchLabels:
            name: web
            app: hello-cloud
        progressDeadlineSeconds: 60
        template:
          metadata:
            labels:
              name: web
              app: hello-cloud
          spec:
            containers:
            - name: app
              image: busybox
              imagePullPolicy: IfNotPresent
              command:
              - tail
              - "-f"
              - "/dev/null"
              ports:
              - containerPort: 80
                name: http
              env:
              - name: FOO
                value: "123e4"
    EOY
    actual = YAML.load_stream(render("pod_with_e_notation_env.yml")).map do |t|
      YAML.dump_k8s_compatible(t)
    end.join
    assert_equal(expected, actual)
  end

  def test_invalid_partial_raises
    err = assert_raises(Krane::InvalidTemplateError) do
      render('broken-partial-inclusion.yaml.erb')
    end
    included_from = "partial included from: broken-partial-inclusion.yaml.erb -> broken.yml.erb"
    assert_match("undefined local variable or method `foo'", err.message)
    assert_match(%r{.*/partials/simple.yaml.erb \(#{included_from}\)}, err.filename)
    assert_equal("c: c3\nd: d4\nfoo: <%= foo %>\n", err.content)
  end

  def test_non_existent_partial_raises
    err = assert_raises(Krane::InvalidTemplateError) do
      render('including-non-existent-partial.yaml.erb')
    end
    base = "Could not find partial 'foobarbaz' in any of"
    assert_match(%r{#{base} .*/fixtures/for_unit_tests/partials:.*/fixtures/partials}, err.message)
    assert_equal("including-non-existent-partial.yaml.erb", err.filename)
    assert_equal("---\n<%= partial 'foobarbaz' %>\n", err.content)
  end

  def test_nesting_fields
    expected = <<~EOY
      ---
      x:
        c: c3
        d: d4
        foo: bar
    EOY
    actual = YAML.dump_k8s_compatible(YAML.safe_load(render("nest-as-rhs.yaml.erb")))
    assert_equal(expected, actual)
    actual = YAML.dump_k8s_compatible(YAML.safe_load(render("nest-indented.yaml.erb")))
    assert_equal(expected, actual)
  end

  def test_deployment_id
    expected = <<~EOY
      ---
      apiVersion: v1
      kind: Pod
      metadata:
        name: migrate-12345678-aaaa
      spec:
        containers:
        - name: migrate
          image: gcr.io/foobar/api
    EOY
    actual = YAML.dump_k8s_compatible(YAML.safe_load(render("deployment_id.yml.erb")))
    assert_equal(expected, actual)
  end

  def test_renderer_without_current_sha_still_has_a_deployment_id
    @renderer = Krane::Renderer.new(
      current_sha: nil,
      template_dir: fixture_path("for_unit_tests"),
      logger: logger,
      bindings: { "a" => "1", "b" => "2" },
    )
    expected = <<~EOY
      ---
      apiVersion: v1
      kind: Pod
      metadata:
        name: migrate-aaaa
      spec:
        containers:
        - name: migrate
          image: gcr.io/foobar/api
    EOY
    actual = YAML.dump_k8s_compatible(YAML.safe_load(render("deployment_id.yml.erb")))
    assert_equal(expected, actual)
  end

  private

  def render(filename)
    raw_template = File.read(File.join(fixture_path('for_unit_tests'), filename))
    @renderer.render_template(filename, raw_template)
  end
end
