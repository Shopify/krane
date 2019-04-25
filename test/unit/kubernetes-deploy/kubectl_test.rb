# frozen_string_literal: true
require 'test_helper'

class KubectlTest < KubernetesDeploy::TestCase
  include StatsDHelper
  include EnvTestHelper

  def setup
    super
    KubernetesDeploy::Kubectl.any_instance.unstub(:run)
    Open3.expects(:capture3).never
  end

  def test_raises_if_initialized_with_null_context
    assert_raises_message(ArgumentError, "context is required") do
      KubernetesDeploy::Kubectl.new(namespace: 'test', context: nil, logger: logger, log_failure_by_default: true)
    end
  end

  def test_raises_if_initialized_with_null_namespace
    assert_raises_message(ArgumentError, "namespace is required") do
      KubernetesDeploy::Kubectl.new(namespace: nil, context: 'test', logger: logger, log_failure_by_default: true)
    end
  end

  def test_run_constructs_the_expected_command_and_returns_the_correct_values
    stub_open3(
      %w(kubectl get pods --output=json) +
      %W(--namespace=testn --context=testc --request-timeout=#{timeout}),
      resp: "{ items: [] }"
    )

    out, err, st = build_kubectl.run("get", "pods", "--output=json")
    assert(st.success?)
    assert_equal("{ items: [] }", out)
    assert_equal("", err)
  end

  def test_run_omits_context_flag_if_use_context_is_false
    stub_open3(
      %w(kubectl get pods --output=json) +
      %W(--namespace=testn --request-timeout=#{timeout}),
      resp: "{ items: [] }"
    )
    build_kubectl.run("get", "pods", "--output=json", use_context: false)
  end

  def test_run_omits_namespace_flag_if_use_namespace_is_false
    stub_open3(
      %w(kubectl get pods --output=json) +
      %W(--context=testc --request-timeout=#{timeout}),
      resp: "{ items: [] }"
    )
    build_kubectl.run("get", "pods", "--output=json", use_namespace: false)
  end

  def test_run_logs_failures_when_log_failure_by_default_is_true_and_override_is_unspecified
    stub_open3(
      %w(kubectl get pods) +
      %W(--namespace=testn --context=testc --request-timeout=#{timeout}),
      resp: "", err: "oops", success: false
    )
    build_kubectl(log_failure_by_default: true).run("get", "pods")
    assert_logs_match("[WARN]", 2)
  end

  def test_run_logs_failures_when_log_failure_by_default_is_true_and_override_is_also_true
    stub_open3(
      %w(kubectl get pods) +
      %W(--namespace=testn --context=testc --request-timeout=#{timeout}),
      resp: "", err: "oops", success: false
    )
    build_kubectl(log_failure_by_default: true).run("get", "pods", log_failure: true)
    assert_logs_match("[WARN]", 2)
  end

  def test_run_does_not_log_failures_when_log_failure_by_default_is_true_and_override_is_false
    stub_open3(
      %w(kubectl get pods) +
      %W(--namespace=testn --context=testc --request-timeout=#{timeout}),
      resp: "", err: "oops", success: false
    )
    build_kubectl(log_failure_by_default: true).run("get", "pods", log_failure: false)
    refute_logs_match("[WARN]")
  end

  def test_run_does_not_log_failures_when_log_failure_by_default_is_false_and_override_is_unspecified
    stub_open3(
      %w(kubectl get pods) +
      %W(--namespace=testn --context=testc --request-timeout=#{timeout}),
      resp: "", err: "oops", success: false
    )
    build_kubectl(log_failure_by_default: false).run("get", "pods")
    refute_logs_match("[WARN]")
  end

  def test_run_does_not_log_failures_when_log_failure_by_default_is_false_and_override_is_also_false
    stub_open3(
      %w(kubectl get pods) +
      %W(--namespace=testn --context=testc --request-timeout=#{timeout}),
      resp: "", err: "oops", success: false
    )
    build_kubectl(log_failure_by_default: false).run("get", "pods", log_failure: false)
    refute_logs_match("[WARN]")
  end

  def test_run_logs_failures_when_log_failure_by_default_is_false_and_override_is_true
    stub_open3(
      %w(kubectl get pods) +
      %W(--namespace=testn --context=testc --request-timeout=#{timeout}),
      resp: "", err: "oops", success: false
    )
    build_kubectl(log_failure_by_default: false).run("get", "pods", log_failure: true)
    assert_logs_match("[WARN]", 2)
  end

  def test_run_with_multiple_attempts_retries_and_emits_failure_metrics
    command = %w(kubectl get pods) +
      %W(--namespace=testn --context=testc --request-timeout=#{timeout})
    Open3.expects(:capture3).with(*command).times(5).returns(["", "oops", stub(success?: false)])
    kubectl = build_kubectl
    kubectl.expects(:retry_delay).returns(0).times(4)

    metrics = capture_statsd_calls do
      _out, _err, st = kubectl.run("get", "pods", attempts: 5)
      refute_predicate st, :success?
    end
    assert_equal(5, metrics.length)
    assert_equal(["KubernetesDeploy.kubectl.error"], metrics.map(&:name).uniq)
  end

  def test_custom_timeout_is_used
    custom_kubectl = KubernetesDeploy::Kubectl.new(namespace: 'testn', context: 'testc', logger: logger,
    log_failure_by_default: true, default_timeout: '5s')
    stub_open3(
      %w(kubectl get pods --namespace=testn --context=testc --request-timeout=5s),
      resp: "", err: "oops", success: false
    )
    custom_kubectl.run("get", "pods", log_failure: true)
    assert_logs_match("[WARN]", 2)
  end

  def test_version_info_returns_the_correct_hash
    stub_version_request(server: version_info(1, 7, 8), client: version_info(1, 7, 10))
    kubectl = build_kubectl
    expected_version_info = { server: Gem::Version.new('1.7.8'), client: Gem::Version.new('1.7.10') }
    assert_equal(expected_version_info, kubectl.version_info)
  end

  def test_client_version_and_server_version_return_the_correct_result
    stub_version_request(server: version_info(1, 7, 8), client: version_info(1, 7, 10))

    kubectl = build_kubectl
    assert_equal("1.7.10", kubectl.client_version.to_s)
    assert_equal("1.7.8", kubectl.server_version.to_s)
  end

  def test_version_comparisons_are_accurate
    stub_version_request(server: version_info(1, 7, 8), client: version_info(1, 7, 8))
    kubectl = build_kubectl
    assert_equal(kubectl.server_version, kubectl.client_version)
    assert(kubectl.server_version < Gem::Version.new('1.7.10'))
    assert(kubectl.server_version > Gem::Version.new('1.7.1'))
    assert(kubectl.server_version < Gem::Version.new('1.8.0'))
  end

  def test_version_methods_work_with_gke_versions
    stub_version_request(
      client: version_info(1, 7, 10),
      server: version_info(1, '7+', 6, git: 'v1.7.6-gke.1')
    )

    kubectl = build_kubectl
    expected_version_info = { client: Gem::Version.new('1.7.10'), server: Gem::Version.new('1.7.6') }
    assert_equal(expected_version_info, kubectl.version_info)
    assert_equal("1.7.10", kubectl.client_version.to_s)
    assert_equal("1.7.6", kubectl.server_version.to_s)
  end

  def test_version_info_raises_if_command_fails
    stub_open3(
      %W(kubectl version --context=testc --request-timeout=#{timeout}),
      resp: '', err: 'bad', success: false
    )
    assert_raises_message(KubernetesDeploy::KubectlError, "Could not retrieve kubectl version info") do
      build_kubectl.version_info
    end
  end

  def test_run_with_raise_if_not_found_raises_the_correct_thing
    err = 'Error from server (NotFound): pods "foobar" not found'
    stub_open3(
      %w(kubectl get pod foobar) +
      %W(--namespace=testn --context=testc --request-timeout=#{timeout}),
      resp: "", err: err, success: false
    )
    assert_raises_message(KubernetesDeploy::Kubectl::ResourceNotFoundError, err) do
      build_kubectl.run("get", "pod", "foobar", raise_if_not_found: true)
    end
  end

  def test_run_with_raise_if_not_found_does_not_raise_on_other_errors
    err = 'Error from server (TooManyRequests): Please try again later'
    stub_open3(
      %w(kubectl get pod foobar) +
      %W(--namespace=testn --context=testc --request-timeout=#{timeout}),
      resp: "", err: err, success: false
    )
    build_kubectl.run("get", "pod", "foobar", raise_if_not_found: true)
  end

  def test_run_output_is_sensitive_squashes_debug_logs
    stub_open3(
      %w(kubectl get pods) +
      %W(--namespace=testn --context=testc --request-timeout=#{timeout}),
      resp: "", err: "oops", success: false
    )
    logger.level = 0
    build_kubectl(log_failure_by_default: false).run("get", "pods", log_failure: false, output_is_sensitive: true)
    refute_logs_match("Kubectl out")
  end

  def test_timeout_errors_are_retried_once_even_if_no_retries_requested
    stub_open3(
      %W(kubectl get namespaces --context=testc --request-timeout=#{timeout}), resp: "",
      success: false, err: "context deadline exceeded (Client.Timeout exceeded while awaiting headers)"
    ).times(2)

    kubectl = build_kubectl
    kubectl.expects(:retry_delay).returns(0).once
    kubectl.run("get", "namespaces", use_namespace: false, attempts: 1)
  end

  def test_timeout_errors_do_not_add_additional_retries_if_some_already_permitted
    stub_open3(
      %W(kubectl get namespaces --context=testc --request-timeout=#{timeout}), resp: "",
      success: false, err: "context deadline exceeded (Client.Timeout exceeded while awaiting headers)"
    ).times(2)

    kubectl = build_kubectl
    kubectl.expects(:retry_delay).returns(0).once
    kubectl.run("get", "namespaces", use_namespace: false, attempts: 2)
  end

  def test_retry_delay_backoff
    ktl = build_kubectl
    max_delay_range = ((KubernetesDeploy::Kubectl::MAX_RETRY_DELAY - 0.5)..KubernetesDeploy::Kubectl::MAX_RETRY_DELAY)
    1000.times do
      assert_includes 0.5..1, ktl.retry_delay(1)
      assert_includes 1.5..2, ktl.retry_delay(2)
      assert_includes 3.5..4, ktl.retry_delay(3)
      assert_includes 7.5..8, ktl.retry_delay(4)
      assert_includes max_delay_range, ktl.retry_delay(5)
      assert_includes max_delay_range, ktl.retry_delay(6)
      assert_includes max_delay_range, ktl.retry_delay(100)
    end
  end

  private

  def timeout
    KubernetesDeploy::Kubectl::DEFAULT_TIMEOUT
  end

  def stub_version_request(client:, server:)
    resp = <<~STRING
      Client Version: #{client}
      Server Version: #{server}
    STRING
    stub_open3(%W(kubectl version --context=testc --request-timeout=#{timeout}), resp: resp)
  end

  def version_info(maj, min, patch, git: nil)
    git ||= "v#{maj}.#{min}.#{patch}"
    <<~STRING
      version.Info{Major:"#{maj}", Minor:"#{min}", GitVersion:"#{git}", GitCommit:"somecommit", GitTreeState:"clean", BuildDate:"2017-09-27T21:21:34Z", GoVersion:"go1.8.3", Compiler:"gc", Platform:"linux/amd64"}
    STRING
  end

  def build_kubectl(log_failure_by_default: true)
    KubernetesDeploy::Kubectl.new(namespace: 'testn', context: 'testc', logger: logger,
      log_failure_by_default: log_failure_by_default)
  end

  def stub_open3(command, resp:, err: "", success: true)
    Open3.expects(:capture3).with(*command).returns([resp, err, stub(success?: success)])
  end
end
