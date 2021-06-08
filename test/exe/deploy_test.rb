# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'

class DeployTest < Krane::TestCase
  def test_deploy_with_default_options
    set_krane_deploy_expectations
    krane_deploy!
  end

  def test_deploy_parses_global_timeout
    set_krane_deploy_expectations(new_args: { global_timeout: 10 })
    krane_deploy!(flags: '--global-timeout 10s')
    set_krane_deploy_expectations(new_args: { global_timeout: 60**2 })
    krane_deploy!(flags: '--global-timeout 1h')
  end

  def test_deploy_parses_selector
    selector = Krane::LabelSelector.new('name' => 'web')
    Krane::LabelSelector.expects(:parse).returns(selector)
    set_krane_deploy_expectations(new_args: { selector: selector })
    krane_deploy!(flags: '--selector name:web')
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
    set_krane_deploy_expectations(new_args: { protected_namespaces: default_namespaces })
    krane_deploy!

    set_krane_deploy_expectations(new_args: { protected_namespaces: ['foo', 'bar'] })
    krane_deploy!(flags: '--protected-namespaces foo bar')

    set_krane_deploy_expectations(new_args: { protected_namespaces: [] })
    krane_deploy!(flags: "--protected-namespaces=''")
  end

  def test_deploy_parses_std_in_alone
    Dir.mktmpdir do |tmp_path|
      $stdin.expects("read").returns("")
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path)
      set_krane_deploy_expectations(new_args: { filenames: [tmp_path] })
      krane_deploy!(flags: '-f -')

      # with deprecated --stdin flag
      $stdin.expects("read").returns("")
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path)
      set_krane_deploy_expectations(new_args: { filenames: [tmp_path] })
      krane_deploy!(flags: '--stdin')
    end
  end

  def test_deploy_parses_std_in_with_multiple_files
    Dir.mktmpdir do |tmp_path|
      $stdin.expects("read").returns("")
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path)
      set_krane_deploy_expectations(new_args: { filenames: ['/my/file/path', tmp_path] })
      krane_deploy!(flags: '-f /my/file/path -')

      # with deprecated --stdin flag
      $stdin.expects("read").returns("")
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path)
      set_krane_deploy_expectations(new_args: { filenames: ['/my/file/path', tmp_path] })
      krane_deploy!(flags: '-f /my/file/path --stdin')
    end
  end

  def test_deploy_passes_filename
    set_krane_deploy_expectations(new_args: { filenames: ['/my/file/path'] })
    krane_deploy!(flags: '-f /my/file/path')
    set_krane_deploy_expectations(new_args: { filenames: ['/my/other/file/path'] })
    krane_deploy!(flags: '--filenames /my/other/file/path')
  end

  def test_deploy_fails_without_filename
    krane = Krane::CLI::Krane.new(
      [deploy_task_config.namespace, deploy_task_config.context],
      []
    )
    assert_raises_message(Thor::RequiredArgumentMissingError, "--filenames must be set and not empty") do
      krane.invoke("deploy")
    end
  end

  def test_stdin_flag_deduped_if_specified_multiple_times
    Dir.mktmpdir do |tmp_path|
      $stdin.expects("read").returns("").times(2)
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path).times(2)
      set_krane_deploy_expectations(new_args: { filenames: [tmp_path] })
      krane_deploy!(flags: '-f - -')

      # with deprecated --stdin flag
      set_krane_deploy_expectations(new_args: { filenames: [tmp_path] })
      krane_deploy!(flags: '-f - --stdin')
    end
  end

  private

  def set_krane_deploy_expectations(new_args: {}, run_args: {})
    options = default_options(new_args, run_args)
    Krane::FormattedLogger.expects(:build).returns(logger)
    response = mock('DeployTask')
    response.expects(:run!).with(options[:run_args]).returns(true)
    Krane::DeployTask.expects(:new).with(options[:new_args]).returns(response)
  end

  def krane_deploy!(flags: '')
    flags += ' -f /tmp' unless flags.include?("-f") || flags.include?("--stdin")
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
        filenames: ['/tmp'],
        logger: logger,
        global_timeout: 300,
        selector: nil,
        selector_as_filter: false,
        protected_namespaces: ["default", "kube-system", "kube-public"],
      }.merge(new_args),
      run_args: {
        verify_result: true,
        prune: true,
      }.merge(run_args),
    }
  end
end
