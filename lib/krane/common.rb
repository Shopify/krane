# frozen_string_literal: true

require 'active_support'
require 'active_support/isolated_execution_state' if ActiveSupport::VERSION::MAJOR > 6
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/reverse_merge'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/string/strip'
require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/array/conversions'
require 'colorized_string'

require 'krane/version'
require 'krane/errors'
require 'krane/formatted_logger'
require 'krane/statsd'
require 'krane/task_config'
require 'krane/task_config_validator'

module Krane
  MIN_KUBE_VERSION = '1.15.0'

  def self.group_from_api_version(input)
    input.include?("/") ? input.split("/").first : ""
  end

  def self.group_kind(group, kind)
    "#{kind}.#{group}"
  end

  def self.group_kind_to_const(group_kind)
    kind, group = group_kind.split(".", 2)

    group = group.split(".").map(&:capitalize).join("")

    group_const = if group == ""
      ::Krane
    else
      ::Krane.const_get(group)
    end

    begin
      klass = group_const.const_get(kind)

      klass
    rescue
      pp(group_kind, group, kind)
      pp(group_const)


      exit
    end
  end
end
