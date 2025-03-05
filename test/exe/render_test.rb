# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'

class RenderTest < Krane::TestCase
  def test_render_with_default_options
    install_krane_render_expectations
    krane_render!
  end

  def test_render_parses_paths
    paths = "/dev/null /dev/yes /dev/no"
    install_krane_render_expectations(filenames: paths.split)
    krane_render!("-f #{paths}")

    install_krane_render_expectations(filenames: paths.split)
    krane_render!("--filenames #{paths}")
  end

  def test_render_parses_std_in
    Dir.mktmpdir do |tmp_path|
      file_path = "/dev/null"
      $stdin.expects("read").returns("")
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path)
      install_krane_render_expectations(filenames: [file_path, tmp_path])
      krane_render!("--filenames #{file_path} -")

      # with deprecated --stdin flag
      $stdin.expects("read").returns("")
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path)
      install_krane_render_expectations(filenames: [file_path, tmp_path])
      krane_render!("--filenames #{file_path} --stdin")
    end
  end

  def test_render_parses_std_in_without_filenames
    Dir.mktmpdir do |tmp_path|
      $stdin.expects("read").returns("")
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path).once
      install_krane_render_expectations(filenames: [tmp_path])
      krane_render!("-f -")

      # with deprecated --stdin flag
      $stdin.expects("read").returns("")
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path).once
      install_krane_render_expectations(filenames: [tmp_path])
      krane_render!("--stdin")
    end
  end

  def test_stdin_flag_deduped_if_specified_multiple_times
    Dir.mktmpdir do |tmp_path|
      $stdin.expects("read").returns("").times(2)
      Dir.expects(:mktmpdir).with("krane").yields(tmp_path).times(2)
      install_krane_render_expectations(filenames: [tmp_path])
      krane_render!('-f - -')

      # with deprecated --stdin flag
      install_krane_render_expectations(filenames: [tmp_path])
      krane_render!('-f - --stdin')
    end
  end

  def test_render_fails_without_filename_and_std_in
    krane = Krane::CLI::Krane.new([], %w(--current-sha 1))

    assert_raises_message(Thor::RequiredArgumentMissingError, "--filenames must be set and not empty") do
      krane.invoke("render")
    end
  end

  def test_render_parses_bindings
    install_krane_render_expectations(bindings: { "foo" => "1", "bar" => "2" })
    krane_render!("-f /dev/null --bindings foo=1,bar=2")
  end

  def test_render_uses_current_sha
    test_sha = "TEST"
    install_krane_render_expectations(current_sha: test_sha)
    krane_render!("--current-sha #{test_sha}")
  end

  def test_render_uses_partials_dir
    install_krane_render_expectations(partials_dir: "/dev/null")
    krane_render!("--partials-dir /dev/null")
  end

  private

  def install_krane_render_expectations(new_args = {})
    options = default_options(new_args)
    response = mock('RenderTask')
    response.expects(:run!).with(stream: STDOUT).returns(true)
    Krane::RenderTask.expects(:new).with(options).returns(response)
  end

  def krane_render!(flags = "")
    flags += ' -f /dev/null' unless flags.include?("-f") || flags.include?("--stdin")
    krane = Krane::CLI::Krane.new(
      [],
      flags.split
    )
    krane.invoke("render")
  end

  def default_options(new_args = {})
    {
      current_sha: nil,
      filenames: ["/dev/null"],
      bindings: {},
      partials_dir: nil,
    }.merge(new_args)
  end
end
