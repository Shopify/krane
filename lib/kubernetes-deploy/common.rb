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

require 'kubernetes-deploy/version'
require 'kubernetes-deploy/oj'
require 'kubernetes-deploy/errors'
require 'kubernetes-deploy/formatted_logger'
require 'kubernetes-deploy/statsd'
require 'kubernetes-deploy/task_config'
require 'kubernetes-deploy/task_config_validator'

module KubernetesDeploy
  MIN_KUBE_VERSION = '1.11.0'
  StatsD.build
end
