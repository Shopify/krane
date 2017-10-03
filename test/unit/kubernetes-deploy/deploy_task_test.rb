# frozen_string_literal: true
require 'test_helper'

class DeployTaskTest < KubernetesDeploy::TestCase
  def test_that_it_has_a_version_number
    refute_nil ::KubernetesDeploy::VERSION
  end

  def test_error_message_when_kubeconfig_not_set
    runner_with_env(nil)
    assert_logs_match("Configuration invalid")
    assert_logs_match("$KUBECONFIG not set")
    assert_logs_match("Current SHA must be specified")
    assert_logs_match("Namespace must be specified")
    assert_logs_match("Context must be specified")
    assert_logs_match(/Template directory (\S+) doesn't exist/)
  end

  def test_initializer
    runner_with_env("/this-really-should/not-exist")
    assert_logs_match("Configuration invalid")
    assert_logs_match("Kube config not found at /this-really-should/not-exist")
    assert_logs_match("Current SHA must be specified")
    assert_logs_match("Namespace must be specified")
    assert_logs_match("Context must be specified")
    assert_logs_match(/Template directory (\S+) doesn't exist/)
  end

  def test_resource_deploy_order_cycle
    task = deploy_task

    list = []
    list << resource_class(kind: 'a', deps: %w(b))
    list << resource_class(kind: 'b', deps: %w(c))
    list << resource_class(kind: 'c', deps: %w(a))

    task.stubs(:all_resources).returns(list)

    assert_raises(KubernetesDeploy::FatalDeploymentError) do
      task._build_predeploy_sequence
    end
  end

  def test_resource_deploy_order_correcntess
    task = deploy_task

    list = []
    list << resource_class(kind: 'a', deps: %w(b k))
    list << resource_class(kind: 'b', deps: [])
    list << resource_class(kind: 'c', deps: %w(h i d))
    list << resource_class(kind: 'd', deps: %w(j h))
    list << resource_class(kind: 'e', deps: [])
    list << resource_class(kind: 'f', deps: %w(e))
    list << resource_class(kind: 'g', deps: [])
    list << resource_class(kind: 'h', deps: [])
    list << resource_class(kind: 'i', deps: %w(j))
    list << resource_class(kind: 'j', deps: %w(g))
    list << resource_class(kind: 'k', deps: %w(i))

    task.stubs(:all_resources).returns(list)
    order = task._build_predeploy_sequence

    # We have the right number of resources
    assert_equal list.count, order.count

    # All resource should be in the list
    list.each { |r| assert_includes order, r.kind }

    # All preconditions should be respected
    order.each_with_index do |r, idx|
      klass = list.detect { |e| e.kind == r }
      klass.predeploy_dependencies.each do |dep|
        pos = order.map.with_index { |e, i| e == dep ? i : nil }.compact.first
        # The current resource is deployed *after* its deps
        assert_operator idx, :>, pos, "#{r} requires #{dep} but got #{order}"
      end
    end
  end

  private

  def resource_class(kind:, deps:)
    klass = Class.new(KubernetesDeploy::KubernetesResource)
    klass.const_set(:PREDEPLOY_DEPENDENCIES, deps)
    klass.const_set(:PREDEPLOY, !deps.empty?)
    klass.stubs(:kind).returns(kind)
    klass
  end

  def deploy_task
    KubernetesDeploy::DeployTask.new(
      namespace: "",
      context: "",
      logger: logger,
      current_sha: "",
      template_dir: "unknown",
    )
  end

  def runner_with_env(value)
    # TODO: Switch to --kubeconfig for kubectl shell out and pass env var as arg to DeployTask init
    # Then fix this crappy env manipulation
    original_env = ENV["KUBECONFIG"]
    ENV["KUBECONFIG"] = value
    deploy_task.run
  ensure
    ENV["KUBECONFIG"] = original_env
  end
end
