# frozen_string_literal: true
require 'test_helper'
require 'krane/cli/krane'

class RendertTest < Krane::TestCase
  include EnvTestHelper
  def test_render_with_default_options
    install_krane_render_expectations
    krane_render!
  end

  def test_render_parses_paths
    paths = "/dev/null /dev/yes /dev/no"
    install_krane_render_expectations(template_paths: paths.split)
    krane_render!("-f #{paths}")

    install_krane_render_expectations(template_paths: paths.split)
    krane_render!("--filenames #{paths}")
  end

  def test_render_parses_bindings
    install_krane_render_expectations(bindings: { "foo" => "1", "bar" => "2" })
    krane_render!("-f /dev/null --bindings foo=1,bar=2")
  end

  def test_render_uses_current_sha
    test_sha = "TEST"
    with_env("REVISION", test_sha) do
      install_krane_render_expectations
      krane_render!
    end
  end

  private

  def install_krane_render_expectations(new_args = {})
    options = default_options(new_args)
    response = mock('RenderTask')
    response.expects(:run!).with(STDOUT).returns(true)
    Krane::RenderTask.expects(:new).with(options).returns(response)
  end

  def krane_render!(flags = '-f /dev/null')
    krane = Krane::CLI::Krane.new(
      [],
      flags.split
    )
    krane.invoke("render")
  end

  def default_options(new_args = {})
    {
      current_sha: ENV["REVISION"],
      template_paths: ["/dev/null"],
      bindings: {},
    }.merge(new_args)
  end
end
