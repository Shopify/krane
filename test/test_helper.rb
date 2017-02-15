$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'kubernetes-deploy'
require 'kubeclient'
require 'pry'
require 'minitest/autorun'

ENV["KUBECONFIG"] ||= "#{Dir.home}/.kube/config"
require 'integration_test'
