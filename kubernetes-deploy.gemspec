# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kubernetes-deploy/version'

Gem::Specification.new do |spec|
  spec.name          = "kubernetes-deploy"
  spec.version       = KubernetesDeploy::VERSION
  spec.authors       = ["Kir Shatrov", "Jean Boussier", "Katrina Verey"]
  spec.email         = ["ops-accounts+shipit@shopify.com"]

  spec.summary       = %q{Kubernetes deploy scripts}
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/Shopify/kubernetes-deploy"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.add_dependency "activesupport", ">= 4.2"
  spec.add_dependency "kubeclient", "~> 2.3"
  spec.add_dependency "googleauth", ">= 0.5"
  spec.add_dependency "ejson", "1.0.1"

  spec.add_development_dependency "bundler", "~> 1.13"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "minitest-stub-const", "~> 0.6"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "mocha", "~> 1.1"
end
