# coding: utf-8
# frozen_string_literal: true
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kubernetes-deploy/version'

Gem::Specification.new do |spec|
  spec.name          = "kubernetes-deploy"
  spec.version       = KubernetesDeploy::VERSION
  spec.authors       = ["Katrina Verey", "Kir Shatrov"]
  spec.email         = ["ops-accounts+shipit@shopify.com"]

  spec.summary       = 'Kubernetes deploy scripts'
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/Shopify/kubernetes-deploy"
  spec.license       = "MIT"

  spec.files         = %x(git ls-files -z).split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = %w(lib)

  spec.required_ruby_version = '>= 2.3.0'
  spec.add_dependency("activesupport", ">= 5.0")
  spec.add_dependency("kubeclient", "~> 4.3")
  spec.add_dependency("googleauth", "~> 0.8.0")
  spec.add_dependency("ejson", "~> 1.0")
  spec.add_dependency("colorize", "~> 0.8")
  spec.add_dependency("statsd-instrument", '~> 2.3', '>= 2.3.2')
  spec.add_dependency("oj", "~> 3.0")
  spec.add_dependency("concurrent-ruby", "~> 1.1")
  spec.add_dependency("jsonpath", "~> 0.9.6")
  spec.add_dependency("thor", "~>  0.20.3")

  spec.add_development_dependency("bundler")
  spec.add_development_dependency("rake", "~> 10.0")
  spec.add_development_dependency("minitest", "~> 5.0")
  spec.add_development_dependency("minitest-stub-const", "~> 0.6")
  spec.add_development_dependency("webmock", "~> 3.0")
  spec.add_development_dependency("mocha", "~> 1.5")
end
