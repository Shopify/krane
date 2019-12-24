# frozen_string_literal: true

require 'test_helper'

module Krane
  class IntegrationTest < Krane::TestCase
    include KubeclientHelper
    include FixtureDeployHelper

    TestProvisioner.prepare_cluster

    if ENV["PARALLELIZE_ME"]
      puts "Running tests in parallel!"
      parallelize_me!
    end

    def run
      super do
        @namespace = TestProvisioner.claim_namespace(name)
        @global_fixtures_deployed = []
      end
    ensure
      TestProvisioner.delete_namespace(@namespace)
      delete_globals(@global_fixtures_deployed)
    end

    def delete_globals(dirs)
      kubectl = build_kubectl
      paths = dirs.flat_map { |d| ["-f", d] }
      kubectl.run("delete", "--wait=false", *paths, log_failure: true, use_namespace: false)
      dirs.each { |dir| FileUtils.remove_entry(dir) }
    end

    def ban_net_connect?
      false
    end

    def prune_matcher(kind, group, name)
      kind + '(.' + group + ')?[ \/]"?' + name + '"?'
    end

    def kube_client_version
      _kubectl.client_version
    end

    def kube_server_version
      _kubectl.server_version
    end

    def server_dry_run_available?
      kube_server_version >= Gem::Version.new('1.13')
    end

    def _kubectl
      @_kubectl ||= Krane::Kubectl.new(task_config: task_config(namespace: "default"),
        log_failure_by_default: true, default_timeout: '5s')
    end
  end
end
