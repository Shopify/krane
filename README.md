# kubernetes-deploy [![Build status](https://badge.buildkite.com/d1aab6d17b010f418e43f740063fe5343c5d65df654e635a8b.svg?branch=master)](https://buildkite.com/shopify/kubernetes-deploy-gem) [![codecov](https://codecov.io/gh/Shopify/kubernetes-deploy/branch/master/graph/badge.svg)](https://codecov.io/gh/Shopify/kubernetes-deploy)

`kubernetes-deploy` is a command line tool that helps you ship changes to a Kubernetes namespace and understand the result. At Shopify, we use it within our much-beloved, open-source [Shipit](https://github.com/Shopify/shipit-engine#kubernetes) deployment app.

Why not just use the standard `kubectl apply` mechanism to deploy? It is indeed a fantastic tool; `kubernetes-deploy` uses it under the hood! However, it leaves its users with some burning questions: _What just happened?_ _Did it work?_

Especially in a CI/CD environment, we need a clear, actionable pass/fail result for each deploy. Providing this was the foundational goal of `kubernetes-deploy`, which has grown to support the following core features:

​:eyes:  Watches the changes you requested to make sure they roll out successfully.

:interrobang: Provides debug information for changes that failed.

:1234:  Predeploys certain types of resources (e.g. ConfigMap, PersistentVolumeClaim) to make sure the latest version will be available when resources that might consume them (e.g. Deployment) are deployed.

:closed_lock_with_key:  [Creates Kubernetes secrets from encrypted EJSON](#deploying-kubernetes-secrets-from-ejson), which you can safely commit to your repository

​:running: [Runs tasks at the beginning of the deploy](#deploy-time-tasks) using bare pods (example use case: Rails migrations)

This repo also includes related tools for [running tasks](#kubernetes-run) and [restarting deployments](#kubernetes-restart).



![demo-deploy.gif](screenshots/deploy-demo.gif)



![missing-secret-fail](screenshots/missing-secret-fail.png)



--------



## Table of contents

**KUBERNETES-DEPLOY**
* [Prerequisites](#prerequisites)
* [Installation](#installation)
* [Usage](#usage)
  * [Using templates and variables](#using-templates-and-variables)
  * [Running tasks at the beginning of a deploy](#running-tasks-at-the-beginning-of-a-deploy)
  * [Deploying Kubernetes secrets (from EJSON)](#deploying-kubernetes-secrets-from-ejson)

**KUBERNETES-RESTART**
* [Usage](#usage-1)

**KUBERNETES-RUN**
* [Prerequisites](#prerequisites-1)
* [Usage](#usage-2)

**DEVELOPMENT**
* [Setup](#setup)
* [Running the test suite locally](#running-the-test-suite-locally)
* [Releasing a new version (Shopify employees)](#releasing-a-new-version-shopify-employees)
* [CI (External contributors)](#ci-external-contributors)

**CONTRIBUTING**
* [Contributing](#contributing)
* [License](#license)


----------



## Prerequisites

* Ruby 2.3+
* Your cluster must be running Kubernetes v1.6.0 or higher
* Each app must have a deploy directory containing its Kubernetes templates (see [Templates](#templates))
* You must remove the` kubectl.kubernetes.io/last-applied-configuration` annotation from any resources in the namespace that are not included in your deploy directory. This annotation is added automatically when you create resources with `kubectl apply`. `kubernetes-deploy` will prune any resources that have this annotation and are not in the deploy directory.**
* Each app managed by `kubernetes-deploy` must have its own exclusive Kubernetes namespace.**


**This requirement can be bypassed with the `--no-prune` option, but it is not recommended.

## Installation

1. [Install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-binary-via-curl) (requires v1.6.0 or higher) and make sure it is available in your $PATH
2. Set up your [kubeconfig file](https://kubernetes.io/docs/tasks/access-application-cluster/authenticate-across-clusters-kubeconfig/) for access to your cluster(s).
3. `gem install kubernetes-deploy`




## Usage

`kubernetes-deploy <app's namespace> <kube context>`

*Environment variables:*

- `$REVISION` **(required)**: the SHA of the commit you are deploying. Will be exposed to your ERB templates as `current_sha`.
- `$KUBECONFIG`  **(required)**: points to one or multiple valid kubeconfig files that include the context you want to deploy to. File names are separated by colon for Linux and Mac, and semi-colon for Windows.
- `$ENVIRONMENT`: used to set the deploy directory to `config/deploy/$ENVIRONMENT`. You can use the `--template-dir=DIR` option instead if you prefer (**one or the other is required**).
- `$GOOGLE_APPLICATION_CREDENTIALS`: points to the credentials for an authenticated service account (required if your kubeconfig `user`'s auth provider is GCP)


*Options:*

Refer to `kubernetes-deploy --help` for the authoritative set of options.

- `--template-dir=DIR`: Used to set the deploy directory. Set `$ENVIRONMENT` instead to use `config/deploy/$ENVIRONMENT`.
- `--bindings=BINDINGS`: Makes additional variables available to your ERB templates. For example, `kubernetes-deploy my-app cluster1 --bindings=color=blue,size=large` will expose `color` and `size`.
- `--no-prune`: Skips pruning of resources that are no longer in your Kubernetes template set. Not recommended, as it allows your namespace to accumulate cruft that is not reflected in your deploy directory.





### Using templates and variables

Each app's templates are expected to be stored in a single directory. If this is not the case, you can create a directory containing symlinks to the templates. The recommended location for app's deploy directory is `{app root}/config/deploy/{env}`, but this is completely configurable.

All templates must be YAML formatted. You can also use ERB. The following local variables will be available to your ERB templates by default:

* `current_sha`: The value of `$REVISION`
* `deployment_id`:  A randomly generated identifier for the deploy. Useful for creating unique names for task-runner pods (e.g. a pod that runs rails migrations at the beginning of deploys).

You can add additional variables using the `--bindings=BINDINGS` option. For example, `kubernetes-deploy my-app cluster1 --bindings=color=blue,size=large` will expose `color` and `size` in your templates.



### Running tasks at the beginning of a deploy

To run a task in your cluster at the beginning of every deploy, simply include a `Pod` template in your deploy directory. `kubernetes-deploy` will first deploy any `ConfigMap` and `PersistentVolumeClaim` resources in your template set, followed by any such pods. If the command run by one of these pods fails (i.e. exits with a non-zero status), the overall deploy will fail at this step (no other resources will be deployed).

*Requirements:*

* The pod's name should include `<%= deployment_id %>` to ensure that a unique name will be used on every deploy (the deploy will fail if a pod with the same name already exists).
* The pod's `spec.restartPolicy` must be set to `Never` so that it will be run exactly once. We'll fail the deploy if that run exits with a non-zero status.
* The pod's `spec.activeDeadlineSeconds` should be set to a reasonable value for the performed task (not required, but highly recommended)

A simple example can be found in the test fixtures: test/fixtures/hello-cloud/unmanaged-pod.yml.erb.

The logs of all pods run in this way will be printed inline.

![migrate-logs](screenshots/migrate-logs.png)



### Deploying Kubernetes secrets (from EJSON)

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



# kubernetes-restart

`kubernetes-restart` is a tool for restarting all of the pods in one or more deployments. It triggers the restart by touching the `RESTARTED_AT` environment variable in the deployment's podSpec. The rollout strategy defined for each deployment will be respected by the restart.



## Usage

**Option 1: Specify the deployments you want to restart**

The following command will restart all pods in the `web` and `jobs` deployments:

`kubernetes-restart <kube namespace> <kube context> --deployments=web,jobs`


**Option 2: Annotate the deployments you want to restart**

Add the annotation `shipit.shopify.io/restart` to all the deployments you want to target, like this:

```yaml
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: web
  annotations:
    shipit.shopify.io/restart: "true"
```

With this done, you can use the following command to restart all of them:

`kubernetes-restart <kube namespace> <kube context>`

# kubernetes-run

`kubernetes-run` is a tool for triggering a one-off job, such as a rake task, _outside_ of a deploy.



## Prerequisites

* You've already deployed a [`PodTemplate`](https://kubernetes.io/docs/api-reference/v1.6/#podtemplate-v1-core) object with field `template` containing a `Pod` specification that does not include the `apiVersion` or `kind` parameters. An example is provided in this repo in `test/fixtures/hello-cloud/template-runner.yml`.
* The `Pod` specification in that template has a container named `task-runner`.

Based on this specification `kubernetes-run` will create a new pod with the entrypoint of the `task-runner ` container overridden with the supplied arguments.



## Usage

`kubernetes-run <kube namespace> <kube context> <arguments> --entrypoint=/bin/bash`

*Options:*

* `--template=TEMPLATE`:  Specifies the name of the PodTemplate to use (default is `task-runner-template` if this option is not set).
* `--env-vars=ENV_VARS`: Accepts a comma separated list of environment variables to be added to the pod template. For example, `--env-vars="ENV=VAL,ENV2=VAL2"` will make `ENV` and `ENV2` available to the container.





# Development

## Setup

If you work for Shopify, just run `dev up`, but otherwise:

1. [Install kubectl version 1.6.0 or higher](https://kubernetes.io/docs/user-guide/prereqs/) and make sure it is in your path
2. [Install minikube](https://kubernetes.io/docs/getting-started-guides/minikube/#installation) (required to run the test suite)
3. Check out the repo
4. Run `bin/setup` to install dependencies

To install this gem onto your local machine, run `bundle exec rake install`.



## Running the test suite locally

1. Start [minikube](https://kubernetes.io/docs/getting-started-guides/minikube/#installation) (`minikube start [options]`)
2. Make sure you have a context named "minikube" in your kubeconfig. Minikube adds this context for you when you run `minikube start`; please do not rename it. You can check for it using `kubectl config get-contexts`.
3. Run `bundle exec rake test`



To see the full-color output of a specific integration test, you can use `PRINT_LOGS=1 bundle exec ruby -I test test/integration/kubernetes_deploy_test.rb -n/test_name/`.

To make StatsD log what it would have emitted, run a test with `STATSD_DEV=1`.



![test-output](screenshots/test-output.png)



## Releasing a new version (Shopify employees)

1. Make sure all merged PRs are reflected in the changelog before creating the commit for the new version.
2. Update the version number in `version.rb` and commit that change with message "Version x.y.z". Don't push yet or you'll confuse Shipit.
3. Tag the version with `git tag vx.y.z -a -m "Version x.y.z"`
4. Push both your bump commit and its tag simultaneously with `git push origin master --follow-tags` (note that you can set `git config --global push.followTags true` to turn this flag on by default)
5. Use the [Shipit Stack](https://shipit.shopify.io/shopify/kubernetes-deploy/rubygems) to build the `.gem` file and upload to [rubygems.org](https://rubygems.org/gems/kubernetes-deploy).

If you push your commit and the tag separately, Shipit usually fails with `You need to create the v0.7.9 tag first.`. To make it find your tag, go to `Settings` > `Resynchronize this stack` > `Clear git cache`.


## CI (External contributors)

Please make sure you run the tests locally before submitting your PR (see [Running the test suite locally](#running-the-test-suite-locally)). After reviewing your PR, a Shopify employee will trigger CI for you.

#### Employees: Triggering CI for a contributed PR

Go to the [kubernetes-deploy-gem pipeline](https://buildkite.com/shopify/kubernetes-deploy-gem) and click "New Build". Use branch `external_contrib_ci` and the specific sha of the commit you want to build. Add `BUILDKITE_REFSPEC="refs/pull/${PR_NUM}/head"` in the Environment Variables section.

<img width="350" alt="build external contrib PR" src="https://screenshot.click/2017-11-07--163728_7ovek-wrpwq.png">

# Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/kubernetes-deploy.

Contributions to help us support additional resource types or increase the sophistication of our success heuristics for an existing type are especially encouraged! (See tips below)



### Contributing a new resource type

The list of fully supported types is effectively the list of classes found in `lib/kubernetes-deploy/kubernetes_resource/`.

This gem uses subclasses of `KubernetesResource` to implement custom success/failure detection logic for each resource type. If no subclass exists for a type you're deploying, the gem simply assumes `kubectl apply` succeeded (and prints a warning about this assumption). We're always looking to support more types! Here are the basic steps for contributing a new one:

1. Create a the file for your type in `lib/kubernetes-deploy/kubernetes_resource/`
2. Create a new class that inherits from `KubernetesResource`. Minimally, it should implement the following methods:
    * `sync` -- gather/update the data you'll need to determine `deploy_succeeded?` and `deploy_failed?`
    * `deploy_succeeded?`
    * `deploy_failed?`
    * `exists?`
3. Adjust the `TIMEOUT` constant to an appropriate value for this type.
4. Add the a basic example of the type to the hello-cloud [fixture set](https://github.com/Shopify/kubernetes-deploy/tree/master/test/fixtures/hello-cloud) and appropriate assertions to `#assert_all_up` in [`hello_cloud.rb`](https://github.com/Shopify/kubernetes-deploy/blob/master/test/helpers/fixture_sets/hello_cloud.rb). This will get you coverage in several existing tests, such as `test_full_hello_cloud_set_deploy_succeeds`.
5. Add tests for any edge cases you foresee.




# License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
