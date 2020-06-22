# frozen_string_literal: true
module Krane
  class ContainerOverrides
    attr_reader :command, :arguments, :env_vars, :image_tag

    def initialize(command: nil, arguments: nil, env_vars: [], image_tag: nil)
      @command = command
      @arguments = arguments
      @env_vars = env_vars
      @image_tag = image_tag
    end

    def apply!(container)
      container.command = command if command
      container.args = arguments if arguments

      if image_tag
        image = container.image
        base_image, _old_tag = image.split(':')
        new_image = "#{base_image}:#{image_tag}"

        container.image = new_image
      end

      env_args = env_vars.map do |env|
        key, value = env.split('=', 2)
        { name: key, value: value }
      end
      container.env ||= []
      container.env = container.env.map(&:to_h) + env_args
    end
  end
end
