# frozen_string_literal: true
require 'test_helper'

module Krane
  class ContainerOverridesTest < Krane::TestCase
    def setup
      super
      @container = Kubeclient::Resource.new(
        name: "task-runner",
        image: "busybox",
        command: ["sh", "-c", "echo 'Hello from the command runner!' "],
        env: [{ name: "CONFIG", value: "NUll" }],
        resources: {},
      )
    end

    def test_updates_command_if_command_is_provided
      override = Krane::ContainerOverrides.new(command: ['/bin/sh', '-c'])
      override.run!(@container)
      assert_equal(['/bin/sh', '-c'], @container.command)
    end

    def test_does_not_update_command_if_not_provided
      override = Krane::ContainerOverrides.new
      override.run!(@container)
      assert_equal(["sh", "-c", "echo 'Hello from the command runner!' "], @container.command)
    end

    def test_updates_image_tag_if_provided
      override = Krane::ContainerOverrides.new(image_tag: 'latest')
      override.run!(@container)
      assert_equal('busybox:latest', @container.image)
    end

    def test_does_not_updates_image_tag_if_not_provided
      override = Krane::ContainerOverrides.new
      override.run!(@container)
      assert_equal('busybox', @container.image)
    end

    def test_updates_args_if_provided
      override = Krane::ContainerOverrides.new(arguments: ['ping'])
      override.run!(@container)
      assert_equal(['ping'], @container.args)
    end

    def test_does_not_updates_args_if_not_provided
      override = Krane::ContainerOverrides.new
      override.run!(@container)
      assert_nil(@container.args)
    end

    def test_updates_env_if_provided
      override = Krane::ContainerOverrides.new(env_vars: ["MY_CUSTOM_VARIABLE=MITTENS"])
      override.run!(@container)
      expectd_env = [
        Kubeclient::Resource.new(name: "CONFIG", value: "NUll"),
        Kubeclient::Resource.new(name: "MY_CUSTOM_VARIABLE", value: "MITTENS"),
      ]
      assert_equal(expectd_env, @container.env)
    end

    def test_does_not_updates_env_if_not_provided
      override = Krane::ContainerOverrides.new
      override.run!(@container)
      expectd_env = [
        Kubeclient::Resource.new(name: "CONFIG", value: "NUll"),
      ]
      assert_equal(expectd_env, @container.env)
    end
  end
end
