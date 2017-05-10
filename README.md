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

 - kubectl 1.6.0+ binary must be available in your path
 - `ENV['KUBECONFIG']` must point to a valid kubeconfig file that includes the context you want to deploy to
 - The target namespace must already exist in the target context
 - `ENV['GOOGLE_APPLICATION_CREDENTIALS']` must point to the credentials for an authenticated service account if your user's auth provider is GCP
 - `ENV['ENVIRONMENT']` must be set to use the default template path (`config/deploy/$ENVIRONMENT`) in the absence of the `--template-dir=DIR` option

The tool also provides a task for restarting all of the pods in one or more deployments.
It triggers the restart by touching the `RESTARTED_AT` environment variable in the deployment's podSpec.
The rollout strategy defined for each deployment will be respected by the restart.

The following command will restart all pods in the `web` and `jobs` deployments:

`kubernetes-restart <kube namespace> <kube context> --deployments=web,jobs`

### Deploying Kubernetes secrets

**Note: If you're a Shopify employee using our cloud platform, this setup has already been done for you. Please consult the CloudPlatform User Guide for usage instructions.**

Since their data is only base64 encoded, Kubernetes secrets should not be committed to your repository. Instead, `kubernetes-deploy` supports generating secrets from an encrypted [ejson](https://github.com/Shopify/ejson) file in your template directory. Here's how to use this feature:

1. Install the ejson gem: `gem install ejson`
2. Generate a new keypair: `ejson keygen` (prints the keypair to stdout)
3. Create a Kubernetes secret in your target namespace with the new keypair: `kubectl create secret generic ejson-keys --from-literal=YOUR_PUBLIC_KEY=YOUR_PRIVATE_KEY --namespace=TARGET_NAMESPACE`
4. (optional but highly recommended) Back up the keypair somewhere secure, such as a password manager, for disaster recovery purposes.
5. In your template directory (alongside your Kubernetes templates), create `secrets.ejson` with the format shown below. The `_type` key should have the value “kubernetes.io/tls” for TLS secrets and “Opaque” for all others. The `data` key must be a json object, but its keys and values can be whatever you need.

```json
{
  "_public_key": "YOUR_PUBLIC_KEY",
  "kubernetes_secrets": {
    "catphotoscom": {
      "_type": "kubernetes.io/tls",
      "data": {
        "tls.crt": "cert-data-here",
        "tls.key": "key-data-here"
      }
    },
    "monitoring-token": {
      "_type": "Opaque",
      "data": {
        "api-token": "token-value-here"
      }
    }
  }
}
```

6. Encrypt the file: `ejson encrypt /PATH/TO/secrets.ejson`
7. Commit the encrypted file and deploy as usual. The deploy will create secrets from the data in the `kubernetes_secrets` key.

**Note**: Since leading underscores in ejson keys are used to skip encryption of the associated value, `kubernetes-deploy` will strip these leading underscores when it creates the keys for the Kubernetes secret data. For example, given the ejson data below, the `monitoring-token` secret will have keys `api-token` and `property` (_not_ `_property`):
```json
{
  "_public_key": "YOUR_PUBLIC_KEY",
  "kubernetes_secrets": {
    "monitoring-token": {
      "_type": "kubernetes.io/tls",
      "data": {
        "api-token": "EJ[ENCRYPTED]",
        "_property": "some unencrypted value"
      }
    }
  }
```

### Running one off tasks

To trigger a one-off job such as a rake task _outside_ of a deploy, use the following command:

`kubernetes-run <kube namespace> <kube context> <arguments> --entrypoint=/bin/bash`

This command assumes that you've already deployed a `PodTemplate` named `task-runner-template`, which contains a full pod specification in its `data`. The pod specification in turn must have a container named `task-runner`. Based on this specification `kubernetes-run` will create a new pod with the entrypoint of the task-runner container overriden with the supplied arguments.

#### Creating a PodTemplate

The [`PodTemplate`](https://kubernetes.io/docs/api-reference/v1.6/#podtemplate-v1-core) object should have a field `template` containing a `Pod` specification which does not include the `apiVersion` or `kind` parameters. An example is provided in this repo in `test/fixtures/hello-cloud/template-runner.yml`.

#### Providing multiple different task-runner configurations

If your application requires task runner templates you can specify which template to use by using the `--template` option. All templates are expected to provide a container called `task-runner`.

#### Specifying environment variables for the container

If you also need to specify environment variables on top of the arguments, you can specify the `--env-vars` flag which accepts a comma separated list of environment variables like so: `--env-vars="ENV=VAL,ENV2=VAL"`


## Development

After checking out the repo, run `bin/setup` to install dependencies. You currently need to [manually install kubectl version 1.6.0 or higher](https://kubernetes.io/docs/user-guide/prereqs/) as well if you don't already have it.

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
