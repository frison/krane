# frozen_string_literal: true
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'kubernetes-deploy'
require 'kubeclient'
require 'pry'
require 'timecop'
require 'minitest/autorun'
require 'minitest/stub/const'

require 'helpers/kubeclient_helper'
require 'helpers/fixture_deploy_helper'
require 'helpers/fixture_set'
require 'helpers/fixture_sets/hello-cloud'

ENV["KUBECONFIG"] ||= "#{Dir.home}/.kube/config"

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

    alias_method :orig_assert_raises, :assert_raises
    def assert_raises(*args)
      case args.last
      when Regexp, String
        flunk("Please use assert_raises_msg to check the exception message. That is not what the last argument of assert_raises does.")
      else
        orig_assert_raises(*args) { yield }
      end
    end

    def assert_raises_msg(exception_class, exception_message)
      exception = orig_assert_raises(exception_class) { yield }
      assert_match exception_message, exception.message
      exception
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
