# frozen_string_literal: true
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'kubernetes-deploy'
require 'kubeclient'
require 'pry'
require 'timecop'
require 'minitest/autorun'
require 'minitest/stub/const'
require 'webmock/minitest'
require 'mocha/mini_test'

Dir.glob(File.expand_path("../helpers/**/*.rb", __FILE__)).each { |file| require file }
ENV["KUBECONFIG"] ||= "#{Dir.home}/.kube/config"

WebMock.allow_net_connect!
Mocha::Configuration.prevent(:stubbing_method_unnecessarily)
Mocha::Configuration.prevent(:stubbing_non_existent_method)
Mocha::Configuration.prevent(:stubbing_non_public_method)

module KubernetesDeploy
  class TestCase < ::Minitest::Test
    def setup
      @logger_stream = StringIO.new
      @logger = ::Logger.new(@logger_stream)
      @logger.level = ::Logger::INFO
      KubernetesDeploy.logger = @logger
      KubernetesResource.logger = @logger
    end

    def teardown
      @logger_stream.close
    end

    def assert_logs_match(regexp, times = nil)
      @logger_stream.rewind
      if times
        count = @logger_stream.read.scan(regexp).count
        assert_equal 1, count, "Expected #{regexp} to appear #{times} time(s) in the log, but appeared #{count} times"
      else
        assert_match regexp, @logger_stream.read
      end
    end

    def assert_raises(*exp, message: nil)
      case exp.last
      when String, Regexp
        raise ArgumentError, "Please use the kwarg message instead of the positional one.\n"\
          "To assert the message exception, use `assert_raises_message` or the return value of `assert_raises`"
      else
        exp += Array(message)
        super(*exp) { yield }
      end
    end

    def assert_raises_message(exception_class, exception_message)
      exception = assert_raises(exception_class) { yield }
      assert_match exception_message, exception.message
      exception
    end

    def fixture_path(set_name)
      source_dir = File.expand_path("../fixtures/#{set_name}", __FILE__)
      raise ArgumentError,
        "Fixture set #{set_name} does not exist as directory #{source_dir}" unless File.directory?(source_dir)
      source_dir
    end
  end

  class IntegrationTest < KubernetesDeploy::TestCase
    include KubeclientHelper
    include FixtureDeployHelper

    def run
      @namespace = TestProvisioner.claim_namespace(name)
      super
    ensure
      TestProvisioner.delete_namespace(@namespace)
    end
  end

  module TestProvisioner
    extend KubeclientHelper

    def self.claim_namespace(test_name)
      test_name = test_name.gsub(/[^-a-z0-9]/, '-').slice(0, 36) # namespace name length must be <= 63 chars
      ns = "k8sdeploy-#{test_name}-#{SecureRandom.hex(8)}"
      create_namespace(ns)
      ns
    rescue KubeException => e
      retry if e.to_s.include?("already exists")
      raise
    end

    def self.create_namespace(namespace)
      ns = Kubeclient::Namespace.new
      ns.metadata = { name: namespace }
      kubeclient.create_namespace(ns)
    end

    def self.delete_namespace(namespace)
      kubeclient.delete_namespace(namespace) if namespace && !namespace.empty?
    rescue KubeException => e
      raise unless e.to_s.include?("not found")
    end

    def self.prepare_pv(name)
      existing_pvs = kubeclient.get_persistent_volumes(label_selector: "name=#{name}")
      return if existing_pvs.present?

      pv = Kubeclient::PersistentVolume.new
      pv.metadata = {
        name: name,
        labels: { name: name }
      }
      pv.spec = {
        accessModes: ["ReadWriteOnce"],
        capacity: { storage: "150Mi" },
        hostPath: { path: "/data/#{name}" },
        persistentVolumeReclaimPolicy: "Recycle"
      }
      kubeclient.create_persistent_volume(pv)
    end
  end

  TestProvisioner.prepare_pv("pv0001")
  TestProvisioner.prepare_pv("pv0002")
end
