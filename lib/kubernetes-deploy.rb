# frozen_string_literal: true

require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/string/strip'
require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/array/conversions'
require 'active_support/duration'
require 'colorized_string'

require 'kubernetes-deploy/version'
require 'kubernetes-deploy/errors'
require 'kubernetes-deploy/formatted_logger'
require 'kubernetes-deploy/statsd'
require 'kubernetes-deploy/deploy_task'
require 'kubernetes-deploy/concurrency'
require 'kubernetes-deploy/bindings_parser'
require 'kubernetes-deploy/duration_parser'
require 'kubernetes-deploy/sync_mediator'

module KubernetesDeploy
  MIN_KUBE_VERSION = '1.9.0'
  KubernetesDeploy::StatsD.build
end
