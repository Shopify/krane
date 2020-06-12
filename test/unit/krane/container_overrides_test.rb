# frozen_string_literal: true
require 'test_helper'

module Krane
  class ContainerOverridesTest < Krane::TestCase
    def setup
      super
      @container = Kubeclient::Resource.new(
        name: "task-runner",
        image: "gcc:3.2",
        command: ["sh", "-c", "echo 'Hello from the command runner!' "],
        env: [{ name: "CONFIG", value: "NUll" }],
        resources: {},
      )
    end

    def test_updates_command
      override = Krane::ContainerOverrides.new(command: ['/bin/sh', '-c'])
      override.run!(@container)
      assert_equal(['/bin/sh', '-c'], @container.command)
    end

    def test_updates_image
      override = Krane::ContainerOverrides.new(image_tag: '4.9')
      override.run!(@container)
      assert_equal('gcc:4.9', @container.image)
    end

    def test_updates_args
      override = Krane::ContainerOverrides.new(arguments: ['ping'])
      override.run!(@container)
      assert_equal(['ping'], @container.args)
    end

    def test_updates_env
      override = Krane::ContainerOverrides.new(env_vars: ["MY_CUSTOM_VARIABLE=MITTENS"])
      override.run!(@container)
      expectd_env = [
        Kubeclient::Resource.new(name: "CONFIG", value: "NUll"),
        Kubeclient::Resource.new(name: "MY_CUSTOM_VARIABLE", value: "MITTENS"),
      ]
      assert_equal(expectd_env, @container.env)
    end
  end
end
