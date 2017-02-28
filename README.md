# Kubernetes::Deploy

[![Build status](https://badge.buildkite.com/0f2d4956d49fbc795f9c17b0a741a6aa9ea532738e5f872ac8.svg?branch=master)](https://buildkite.com/shopify/kubernetes-deploy-gem)

Deploy script used to manage a Kubernetes application's namespace with [Shipit](https://github.com/Shopify/shipit-engine).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'kubernetes-deploy'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kubernetes-deploy

## Usage

`kubernetes-deploy <app's namespace> <kube context> --template-dir=DIR`

Requirements:

 - kubectl 1.5.1+ binary must be available in your path
 - `ENV['KUBECONFIG']` must point to a valid kubeconfig file that includes the context you want to deploy to
 - `ENV['GOOGLE_APPLICATION_CREDENTIALS']` must point to the credentials for an authenticated service account if your user's auth provider is gcp
 - `ENV['ENVIRONMENT']` must be set to use the default template path (`config/deploy/$ENVIRONMENT`) in the absence of the `--template-dir=DIR` option


## Development

After checking out the repo, run `bin/setup` to install dependencies. You currently need to [manually install kubectl version 1.5.1 or higher](https://kubernetes.io/docs/user-guide/prereqs/) as well if you don't already have it.

To run the tests:

* [Install minikube](https://kubernetes.io/docs/getting-started-guides/minikube/#installation)
* Start minikube (`minikube start [options]`)
* Make sure you have a context named "minikube" in your kubeconfig. Minikube adds this context for you when you run `minikube start`; please do not rename it. You can check for it using `kubectl config get-contexts`.
* Run `bundle exec rake test`

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## CI

Buildkite will build branches as you're working on them, but as soon as you create a PR it will stop building new commits from that branch because we disabled PR builds for security reasons.
As a Shopify employee, you can manually trigger the PR build from the Buildkite UI (just specify the branch, SHA is not required):

<img width="464" alt="screen shot 2017-02-21 at 10 55 33" src="https://cloud.githubusercontent.com/assets/522155/23172610/52771a3a-f824-11e6-8c8e-3d59c45e7ff8.png">


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/kubernetes-deploy.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
