# frozen_string_literal: true

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
require 'krane/oj'
require 'krane/errors'
require 'krane/formatted_logger'
require 'krane/statsd'
require 'krane/task_config'
require 'krane/task_config_validator'

module Krane
  MIN_KUBE_VERSION = '1.11.0'
end
