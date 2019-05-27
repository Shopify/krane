# frozen_string_literal: true

require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/reverse_merge'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/string/strip'
require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/array/conversions'
require 'active_support/duration'
require 'colorized_string'

require 'kubernetes-deploy/version'
require 'kubernetes-deploy/oj'
require 'kubernetes-deploy/errors'
require 'kubernetes-deploy/formatted_logger'
require 'kubernetes-deploy/options_helper'
require 'kubernetes-deploy/statsd'
require 'kubernetes-deploy/deploy_task'
require 'kubernetes-deploy/concurrency'
require 'kubernetes-deploy/bindings_parser'
require 'kubernetes-deploy/duration_parser'
require 'kubernetes-deploy/resource_cache'
require 'kubernetes-deploy/label_selector'

module KubernetesDeploy
  MIN_KUBE_VERSION = '1.10.0'
  StatsD.build
end
