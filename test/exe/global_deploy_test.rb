# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'
require 'krane/global_deploy_task'

class GlobalDeployTest < Krane::TestCase
  def test_global_deploy_with_default_options
    set_krane_global_deploy_expectations!
    krane_global_deploy!
  end

  def test_deploy_parses_global_timeout
    set_krane_global_deploy_expectations!(new_args: { global_timeout: 10 })
    krane_global_deploy!(flags: '--global-timeout 10s')
    set_krane_global_deploy_expectations!(new_args: { global_timeout: 60**2 })
    krane_global_deploy!(flags: '--global-timeout 1h')
  end

  def test_deploy_passes_verify_result
    set_krane_global_deploy_expectations!(run_args: { verify_result: true })
    krane_global_deploy!(flags: '--verify-result true')
    set_krane_global_deploy_expectations!(run_args: { verify_result: false })
    krane_global_deploy!(flags: '--verify-result false')
  end

  def test_deploy_parses_std_in_without_filenames
    Dir.mktmpdir do |tmp_path|
      $stdin.expects("read").returns("")
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path)
      set_krane_global_deploy_expectations!(new_args: { filenames: [tmp_path] })
      krane_global_deploy!(flags: '--stdin')
    end
  end

  def test_deploy_passes_filename
    set_krane_global_deploy_expectations!(new_args: { filenames: ['/my/file/path'] })
    krane_global_deploy!(flags: '-f /my/file/path')
    set_krane_global_deploy_expectations!(new_args: { filenames: %w(/my/other/file/path just/a/file.yml) })
    krane_global_deploy!(flags: '--filenames /my/other/file/path just/a/file.yml')
  end

  def test_deploy_parses_std_in
    Dir.mktmpdir do |tmp_path|
      $stdin.expects("read").returns("")
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path)
      set_krane_global_deploy_expectations!(new_args: { filenames: ['/my/file/path', tmp_path] })
      krane_global_deploy!(flags: '-f /my/file/path --stdin')
    end
  end

  def test_deploy_fails_without_filename_and_std_in
    krane = Krane::CLI::Krane.new([task_config.context], %w(--selector app=krane))
    assert_raises_message(Thor::RequiredArgumentMissingError, "At least one of --filenames or --stdin must be set") do
      krane.invoke("global_deploy")
    end
  end

  def test_deploy_parses_selector
    selector = 'name=web'
    set_krane_global_deploy_expectations!(new_args: { selector: selector })
    krane_global_deploy!(flags: "--selector #{selector}")
  end

  def test_deploy_parses_prune
    set_krane_global_deploy_expectations!(run_args: { prune: false })
    krane_global_deploy!(flags: '--prune false')
  end

  private

  def set_krane_global_deploy_expectations!(new_args: {}, run_args: {})
    options = default_options(new_args, run_args)
    response = mock('GlobalDeployTask')
    response.expects(:run!).with(options[:run_args]).returns(true)
    Krane::GlobalDeployTask.expects(:new).with do |args|
      args.except(:selector) == options[:new_args].except(:selector) &&
      args[:selector].to_s == options[:new_args][:selector]
    end.returns(response)
  end

  def krane_global_deploy!(flags: '')
    flags += ' -f /tmp' unless flags.include?('-f') || flags.include?('--stdin')
    flags += ' --selector name=web' unless flags.include?('--selector')
    krane = Krane::CLI::Krane.new(
      [task_config.context],
      flags.split
    )
    krane.invoke("global_deploy")
  end

  def default_options(new_args = {}, run_args = {})
    {
      new_args: {
        context: task_config.context,
        filenames: ['/tmp'],
        global_timeout: 300,
        selector: 'name=web',
      }.merge(new_args),
      run_args: {
        verify_result: true,
        prune: true,
      }.merge(run_args),
    }
  end
end
