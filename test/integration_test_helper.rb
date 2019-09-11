# frozen_string_literal: true

require 'test_helper'

module KubernetesDeploy
  class IntegrationTest < KubernetesDeploy::TestCase
    include KubeclientHelper
    include FixtureDeployHelper

    TestProvisioner.prepare_cluster

    if ENV["PARALLELIZE_ME"]
      puts "Running tests in parallel!"
      parallelize_me!
    end

    def run
      super { @namespace = TestProvisioner.claim_namespace(name) }
    ensure
      TestProvisioner.delete_namespace(@namespace)
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
      @server_dry_run ||= begin
        file_path = "#{fixture_path('hello-cloud')}/service-account.yml"
        command = ["apply", "-f", file_path, "--server-dry-run", "--output=name"]
        _, _, st = _kubectl.run(*command, log_failure: false, attempts: 3)
        st.success?
      end
    end

    def _kubectl
      @_kubectl ||= KubernetesDeploy::Kubectl.new(namespace: "default", context: TEST_CONTEXT, logger: logger,
        log_failure_by_default: true, default_timeout: '5s')
    end
  end
end
