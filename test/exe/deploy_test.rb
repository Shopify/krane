# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'
require 'krane/bindings_parser'

class DeployTest < KubernetesDeploy::TestCase
  def test_deploy_with_default_options
    set_krane_deploy_expectations
    krane_deploy!
  end

  def test_deploy_parses_global_timeout
    set_krane_deploy_expectations(new_args: { max_watch_seconds: 10 })
    krane_deploy!(flags: '--global-timeout 10s')
    set_krane_deploy_expectations(new_args: { max_watch_seconds: 60**2 })
    krane_deploy!(flags: '--global-timeout 1h')
  end

  def test_deploy_parses_selector
    selector = KubernetesDeploy::LabelSelector.new('name' => 'web')
    KubernetesDeploy::LabelSelector.expects(:parse).returns(selector)
    set_krane_deploy_expectations(new_args: { selector: selector })
    krane_deploy!(flags: '--selector name:web')
  end

  def test_deploy_parses_bindings
    bindings_parser = KubernetesDeploy::BindingsParser.new
    bindings_parser.expects(:add).with('foo=bar')
    bindings_parser.expects(:add).with('abc=def')
    bindings_parser.expects(:parse).returns(true)
    KubernetesDeploy::BindingsParser.expects(:new).returns(bindings_parser)
    set_krane_deploy_expectations(new_args: { bindings: true })
    krane_deploy!(flags: '--bindings foo=bar abc=def')
  end

  def test_deploy_passes_verify_result
    set_krane_deploy_expectations(run_args: { verify_result: true })
    krane_deploy!(flags: '--verify-result true')
    set_krane_deploy_expectations(run_args: { verify_result: false })
    krane_deploy!(flags: '--verify-result false')
  end

  def test_deploy_passes_prune
    set_krane_deploy_expectations(run_args: { prune: true })
    krane_deploy!
    set_krane_deploy_expectations(run_args: { prune: false })
    krane_deploy!(flags: '--no-prune')
  end

  def test_deploy_passes_protected_namespaces
    default_namespaces = %w(default kube-system kube-public)
    set_krane_deploy_expectations(new_args: { protected_namespaces: default_namespaces },
      run_args: { allow_protected_ns: true })
    krane_deploy!

    set_krane_deploy_expectations(new_args: { protected_namespaces: ['foo', 'bar'] },
      run_args: { allow_protected_ns: true })
    krane_deploy!(flags: '--protected-namespaces foo bar')

    set_krane_deploy_expectations(new_args: { protected_namespaces: [] },
      run_args: { allow_protected_ns: false })
    krane_deploy!(flags: "--protected-namespaces=''")
  end

  def test_deploy_passes_filename
    set_krane_deploy_expectations(new_args: { template_paths: ['/my/file/path'] })
    krane_deploy!(flags: '-f /my/file/path')
    set_krane_deploy_expectations(new_args: { template_paths: ['/my/other/file/path'] })
    krane_deploy!(flags: '--filenames /my/other/file/path')
  end

  def test_deploy_fails_without_filename
    krane = Krane::CLI::Krane.new(
      [deploy_task_config.namespace, deploy_task_config.context],
      []
    )
    assert_raises_message(Thor::RequiredArgumentMissingError, "No value provided for required options '--filenames'") do
      krane.invoke("deploy")
    end
  end

  private

  def set_krane_deploy_expectations(new_args: {}, run_args: {})
    options = default_options(new_args, run_args)
    KubernetesDeploy::FormattedLogger.expects(:build).returns(logger)
    response = mock('DeployTask')
    response.expects(:run!).with(options[:run_args]).returns(true)
    KubernetesDeploy::DeployTask.expects(:new).with(options[:new_args]).returns(response)
  end

  def krane_deploy!(flags: '')
    flags += ' -f /tmp' unless flags.include?('-f')
    krane = Krane::CLI::Krane.new(
      [deploy_task_config.namespace, deploy_task_config.context],
      flags.split
    )
    krane.invoke("deploy")
  end

  def deploy_task_config
    @deploy_config ||= task_config(namespace: 'test-namespace')
  end

  def default_options(new_args = {}, run_args = {})
    {
      new_args: {
        namespace: deploy_task_config.namespace,
        context: deploy_task_config.context,
        current_sha: nil,
        template_paths: ['/tmp'],
        bindings: {},
        logger: logger,
        max_watch_seconds: 300,
        selector: nil,
        protected_namespaces: ["default", "kube-system", "kube-public"],
      }.merge(new_args),
      run_args: {
        verify_result: true,
        allow_protected_ns: true,
        prune: true,
      }.merge(run_args),
    }
  end
end
