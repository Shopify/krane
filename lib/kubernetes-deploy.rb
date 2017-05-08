# frozen_string_literal: true
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/string/strip'
require 'active_support/core_ext/hash/keys'

require 'kubernetes-deploy/errors'
require 'kubernetes-deploy/logger'
require 'kubernetes-deploy/runner'

module KubernetesDeploy
  include Logger
end
