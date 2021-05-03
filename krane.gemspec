# coding: utf-8
# frozen_string_literal: true
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'krane/version'

Gem::Specification.new do |spec|
  spec.name          = "krane"
  spec.version       = Krane::VERSION
  spec.authors       = ["Katrina Verey", "Daniel Turner", "Kir Shatrov"]
  spec.email         = ["ops-accounts+shipit@shopify.com"]

  spec.summary       = 'A command line tool that helps you ship changes to a Kubernetes' \
    ' namespace and understand the result'
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/Shopify/krane"
  spec.license       = "MIT"

  spec.files         = %x(git ls-files -z).split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = %w(lib)

  spec.metadata['allowed_push_host'] = "https://rubygems.org"

  spec.required_ruby_version = '>= 2.6.0'
  spec.add_dependency("activesupport", ">= 5.0")
  spec.add_dependency("kubeclient", "~> 4.3")
  spec.add_dependency("googleauth", "~> 0.8")
  spec.add_dependency("ejson", "~> 1.0")
  spec.add_dependency("colorize", "~> 0.8")
  spec.add_dependency("statsd-instrument", ['>= 2.8', "< 4"])
  spec.add_dependency("oj", "~> 3.0")
  spec.add_dependency("concurrent-ruby", "~> 1.1")
  spec.add_dependency("jsonpath", "~> 0.9.6")
  spec.add_dependency("thor", ">= 1.0", "< 2.0")

  # Basics
  spec.add_development_dependency("bundler")
  spec.add_development_dependency("rake", "~> 10.0")
  spec.add_development_dependency("yard")

  # Test framework
  spec.add_development_dependency("minitest", "~> 5.12")
  spec.add_development_dependency("minitest-stub-const", "~> 0.6")
  spec.add_development_dependency("minitest-reporters")
  spec.add_development_dependency("mocha", "~> 1.5")
  spec.add_development_dependency("webmock", "~> 3.0")
  spec.add_development_dependency("timecop")

  # Debugging and analysis
  spec.add_development_dependency("pry")
  spec.add_development_dependency("pry-byebug")
  spec.add_development_dependency("byebug")
  spec.add_development_dependency("ruby-prof")
  spec.add_development_dependency("ruby-prof-flamegraph")
  spec.add_development_dependency("rubocop", "~> 0.89.1")
  spec.add_development_dependency("rubocop-shopify", "~> 1.0.5")
  spec.add_development_dependency("simplecov")
end
