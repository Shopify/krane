# kubernetes-deploy [![Build status](https://badge.buildkite.com/d1aab6d17b010f418e43f740063fe5343c5d65df654e635a8b.svg?branch=master)](https://buildkite.com/shopify/kubernetes-deploy-gem) [![codecov](https://codecov.io/gh/Shopify/kubernetes-deploy/branch/master/graph/badge.svg)](https://codecov.io/gh/Shopify/kubernetes-deploy)

`kubernetes-deploy` is a command line tool that helps you ship changes to a Kubernetes namespace and understand the result. At Shopify, we use it within our much-beloved, open-source [Shipit](https://github.com/Shopify/shipit-engine#kubernetes) deployment app.

Why not just use the standard `kubectl apply` mechanism to deploy? It is indeed a fantastic tool; `kubernetes-deploy` uses it under the hood! However, it leaves its users with some burning questions: _What just happened?_ _Did it work?_

Especially in a CI/CD environment, we need a clear, actionable pass/fail result for each deploy. Providing this was the foundational goal of `kubernetes-deploy`, which has grown to support the following core features:

​:eyes:  Watches the changes you requested to make sure they roll out successfully.

:interrobang: Provides debug information for changes that failed.

:1234:  Predeploys certain types of resources (e.g. ConfigMap, PersistentVolumeClaim) to make sure the latest version will be available when resources that might consume them (e.g. Deployment) are deployed.

:closed_lock_with_key:  [Creates Kubernetes secrets from encrypted EJSON](#deploying-kubernetes-secrets-from-ejson), which you can safely commit to your repository

​:running: [Running tasks at the beginning of a deploy](#running-tasks-at-the-beginning-of-a-deploy) using bare pods (example use case: Rails migrations)

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
  * [Customizing behaviour with annotations](#customizing-behaviour-with-annotations)
  * [Running tasks at the beginning of a deploy](#running-tasks-at-the-beginning-of-a-deploy)
  * [Deploying Kubernetes secrets (from EJSON)](#deploying-kubernetes-secrets-from-ejson)
  * [Deploying custom resources](#deploying-custom-resources)

**KUBERNETES-RESTART**
* [Usage](#usage-1)

**KUBERNETES-RUN**
* [Prerequisites](#prerequisites-1)
* [Usage](#usage-2)

**KUBERNETES-RENDER**
* [Prerequisites](#prerequisites-2)
* [Usage](#usage-3)

**DEVELOPMENT**
* [Setup](#setup)
* [Running the test suite locally](#running-the-test-suite-locally)
* [Releasing a new version (Shopify employees)](#releasing-a-new-version-shopify-employees)
* [CI (External contributors)](#ci-external-contributors)

**CONTRIBUTING**
* [Contributing](#contributing)
* [Code of Conduct](#code-of-conduct)
* [License](#license)


----------



## Prerequisites

* Ruby 2.3+
* Your cluster must be running Kubernetes v1.10.0 or higher<sup>1</sup>
* Each app must have a deploy directory containing its Kubernetes templates (see [Templates](#using-templates-and-variables))
* You must remove the` kubectl.kubernetes.io/last-applied-configuration` annotation from any resources in the namespace that are not included in your deploy directory. This annotation is added automatically when you create resources with `kubectl apply`. `kubernetes-deploy` will prune any resources that have this annotation and are not in the deploy directory.<sup>2</sup>
* Each app managed by `kubernetes-deploy` must have its own exclusive Kubernetes namespace.

<sup>1</sup> We run integration tests against these Kubernetes versions. You can find our
offical compatibility chart below.

<sup>2</sup> This requirement can be bypassed with the `--no-prune` option, but it is not recommended.

| Kubernetes version | Last officially supported in gem version |
| :----------------: | :-------------------: |
|        1.5         |        0.11.2         |
|        1.6         |        0.15.2         |
|        1.7         |        0.20.6         |
|        1.8         |        0.21.1         |

## Installation

1. [Install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-binary-via-curl) (requires v1.10.0 or higher) and make sure it is available in your $PATH
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
- `--max-watch-seconds=seconds`: Raise a timeout error if it takes longer than _seconds_ for any
resource to deploy.


### Using templates and variables

Each app's templates are expected to be stored in a single directory. If this is not the case, you can create a directory containing symlinks to the templates. The recommended location for app's deploy directory is `{app root}/config/deploy/{env}`, but this is completely configurable.

All templates must be YAML formatted. You can also use ERB. The following local variables will be available to your ERB templates by default:

* `current_sha`: The value of `$REVISION`
* `deployment_id`:  A randomly generated identifier for the deploy. Useful for creating unique names for task-runner pods (e.g. a pod that runs rails migrations at the beginning of deploys).

You can add additional variables using the `--bindings=BINDINGS` option which can be formated as comma separated string, JSON string or path to a JSON or YAML file. Complex JSON or YAML data will be converted to a Hash for use in templates. To load a file the argument should include the relative file path prefixed with an `@` sign. An argument error will be raised if the string argument cannot be parsed, the referenced file does not include a valid extension (`.json`, `.yaml` or `.yml`) or the referenced file does not exist.

#### Bindings examples

```
# Comma separated string. Exposes, 'color' and 'size'
$ kubernetes-deploy my-app cluster1 --bindings=color=blue,size=large

# JSON string. Exposes, 'color' and 'size'
$ kubernetes-deploy my-app cluster1 --bindings='{"color":"blue","size":"large"}'

# Load JSON file from ./config
$ kubernetes-deploy my-app cluster1 --bindings='@config/production.json'

# Load YAML file from ./config (.yaml or .yml supported)
$ kubernetes-deploy my-app cluster1 --bindings='@config/production.yaml'
```


#### Using partials

`kubernetes-deploy` supports composing templates from so called partials in order to reduce duplication in Kubernetes YAML files. Given a template directory `DIR`, partials are searched for in `DIR/partials`and in 'DIR/../partials', in that order. They can be embedded in other ERB templates using the helper method `partial`. For example, let's assume an application needs a number of different CronJob resources, one could place a template called `cron` in one of those directories and then use it in the main deployment.yaml.erb like so:

```yaml
<%= partial "cron", name: "cleanup",   schedule: "0 0 * * *", args: %w(cleanup),    cpu: "100m", memory: "100Mi" %>
<%= partial "cron", name: "send-mail", schedule: "0 0 * * *", args: %w(send-mails), cpu: "200m", memory: "256Mi" %>
```

Inside a partial, parameters can be accessed as normal variables, or via a hash called `locals`. Thus, the `cron` template could like this:

```yaml
---
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: cron-<%= name %>
spec:
  schedule: <%= schedule %>
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cron-<%= name %>
            image: ...
            args: <%= args %>
            resources:
              requests:
                cpu: "<%= cpu %>"
                memory: <%= memory %>
          restartPolicy: OnFailure
```

Both `.yaml.erb` and `.yml.erb` file extensions are supported. Templates must refer to the bare filename (e.g. use `partial: 'cron'` to reference `cron.yaml.erb`).

##### Limitations when using partials

Partials can be included almost everywhere in ERB templates. Note: when using a partial to insert additional key-value pairs to a map you must use [YAML merge keys](http://yaml.org/type/merge.html). For example, given a partial `p` defining two fields 'a' and 'b',

```yaml
a: 1
b: 2
```

you cannot do this:

```yaml
x: yz
<%= partial 'p' %>
```

hoping to get

```yaml
x: yz
a: 1
b: 2
```

but you can do:

```yaml
<<: <%= partial 'p' %>
x: yz
```

This is a limitation of the current implementation.


### Customizing behaviour with annotations
- `kubernetes-deploy.shopify.io/timeout-override`: Override the tool's hard timeout for one specific resource. Both full ISO8601 durations and the time portion of ISO8601 durations are valid. Value must be between 1 second and 24 hours.
  - _Example values_: 45s / 3m / 1h / PT0.25H
  - _Compatibility_: all resource types (Note: `Deployment` timeouts are based on `spec.progressDeadlineSeconds` if present, and that field has a default value as of the `apps/v1beta1` group version. Using this annotation will have no effect on `Deployment`s that time out with "Timeout reason: ProgressDeadlineExceeded".)
- `kubernetes-deploy.shopify.io/required-rollout`: Modifies how much of the rollout needs to finish
before the deployment is considered successful.
  - _Compatibility_: Deployment
  - `full`: The deployment is successful when all pods in the new `replicaSet` are ready.
  - `none`: The deployment is successful as soon as the new `replicaSet` is created for the deployment.
  - `maxUnavailable`: The deploy is successful when minimum availability is reached in the new `replicaSet`.
  In other words, the number of new pods that must be ready is equal to `spec.replicas` - `strategy.RollingUpdate.maxUnavailable`
  (converted from percentages by rounding up, if applicable). This option is only valid for deployments
  that use the `RollingUpdate` strategy.
  - Percent (e.g. 90%): The deploy is successful when the number of new pods that are ready is equal to
  `spec.replicas` * Percent.
- `kubernetes-deploy.shopify.io/prunable`: Allows a Custom Resource to be pruned during deployment.
  - _Compatibility_: Custom Resource Definition
  - `true`: The custom resource will be pruned if the resource is not in the deploy directory.
  - All other values: The custom resource will not be pruned.

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

### Deploying custom resources

By default, kubernetes-deploy does not check to see whether the deployment of a custom resource is successful or not. Instead, it simply assumes that the custom resource deploys successfully and performs no additional checks. In order to meaningfully monitor the rollout of custom resources, kubernetes-deploy supports annotations that specify the pass/fail conditions of a given resource.

*Requirements:*

>Note:
This feature is only available on clusters running Kubernetes 1.11+ since it relies on the `metadata.generation` field being updated when custom resource specs are changed.

* The custom resource must expose a `status` field with an `observedGeneration` field.
* The `kubernetes-deploy.shopify.io/instance-rollout-conditions` annotation must be present on the *CRD* that defines the custom resource.
* (optional) The `kubernetes-deploy.shopify.io/cr-instance-timeout` annotation can be added to the *CRD* that defines the custom resource to specify a default timeout for all instances of the CRD (otherwise the global default is used).

### Specifying pass/fail conditions

The presence of a valid `kubernetes-deploy.shopify.io/instance-rollout-conditions` annotation on a CRD will cause kubernetes-deploy to monitor the rollout of any of its instances with the supplied annotation value. This value must be a valid JSON string with the following format:
```
'{
  "success_conditions": [
    { "path": <JsonPath expression>, "value": <target value> }
    ... more success conditions
  ],
  "failure_conditions": [
    { "path": <JsonPath expression>, "value": <target value> }
    ... more failure conditions
  ]
}'
```

For all conditions, `path` must be a valid JsonPath expression that points to a given field in the custom resource's spec. `value` is the value that must be present at `path` in order to fulfill a condition. For a deployment to be successful, _all_ `success_conditions` must be fulfilled. Conversely, it is sufficient for _any one of_ `failure_conditions` to be fulfilled in order to mark the deploy as failed.

**Warning:**

You **must** ensure that your custom resource controller sets `.status.observedGeneration` to `.metadata.generation` of the monitored resource once its sync is complete. If this does not happen, kubernetes-deploy will not check success or failure conditions and the deploy will timeout.

### Example

As an example, observe the following default rollout configuration. You can use this default by setting `kubernetes-deploy.shopify.io/instance-rollout-conditions: "true"` on the *CRD* that defines the custom resources you wish to monitor. This will create a rollout configuration identical to this specification:

```
'{
  "success_conditions": [
    {
      "path": "$.status.conditions[?(@.type == \"Ready\")].status",
      "value": "True",
    },
  ],
  "failure_conditions": [
    {
      "path": '$.status.conditions[?(@.type == \"Failed\")].status',
      "value": "True",
      "error_msg_path": '$.status.conditions[?(@.type == \"Failed\")].message',
    },
  ],
}'
```

The paths defined here are based on the [typical status properties](https://github.com/kubernetes/community/blob/master/contributors/devel/api-conventions.md#typical-status-properties) as defined by the Kubernetes community. It expects the `status` subresource to contain a `conditions` array whose entries minimally specify `type`, `status`, and `message` fields. Note that the failure condition uses the optional `error_msg_path` field that will output the contents of the path specified when the deploy fails due to that condition. As an alternative, `custom_error_msg` can be used if you want to provide a message that isn't exposed by the resource itelf. Note that `error_msg_path` and `custom_error_msg` are optional fields and not strictly required.

You can see how these conditions relate to the following resource:

```
apiVersion: stable.shopify.io/v1
kind: Example
metadata:
  generation: 2
  name: example
  namespace: namespace
spec:
  ...
status:
  observedGeneration: 2
  conditions:
  - type: "Ready"
    status: "False"
    reason: "exampleNotReady"
    message: "resource is not ready"
  - type: "Failed"
    status: "True"
    message: "resource is failed"
    reason: "exampleFailed"
```

- `observedGeneration == metadata.generation`, so kubernetes-deploy will monitor the deploy.
- Since `$.status.conditions[?(@.type == "Ready")].status == "False"`, the deploy is not considered successful yet.
- `$.status.conditions[?(@.type == "Failed")].status == "True"` means that a failure condition has been fulfilled and the deploy is considered failed.
- Since `error_msg_path` is specified, kubernetes-deploy will log the contents of '$.status.conditions[?(@.type == "Failed")].message', which in this case is: `resource is failed`.

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

* You've already deployed a [`PodTemplate`](https://v1-10.docs.kubernetes.io/docs/reference/generated/kubernetes-api/v1.10/#podtemplate-v1-core) object with field `template` containing a `Pod` specification that does not include the `apiVersion` or `kind` parameters. An example is provided in this repo in `test/fixtures/hello-cloud/template-runner.yml`.
* The `Pod` specification in that template has a container named `task-runner`.

Based on this specification `kubernetes-run` will create a new pod with the entrypoint of the `task-runner ` container overridden with the supplied arguments.



## Usage

`kubernetes-run <kube namespace> <kube context> <arguments> --entrypoint=<entrypoint> --template=<template name>`

*Options:*

* `--template=TEMPLATE`:  Specifies the name of the PodTemplate to use (default is `task-runner-template` if this option is not set).
* `--env-vars=ENV_VARS`: Accepts a comma separated list of environment variables to be added to the pod template. For example, `--env-vars="ENV=VAL,ENV2=VAL2"` will make `ENV` and `ENV2` available to the container.
* `--entrypoint=ENTRYPOINT`: Specify the entrypoint to use to start the task runner container.
* `--skip-wait`: Skip verification of pod success
* `--max-watch-seconds=seconds`: Raise a timeout error if the pod runs for longer than the specified number of seconds



# kubernetes-render

`kubernetes-render` is a tool for rendering ERB templates to raw Kubernetes YAML. It's useful for seeing what `kubernetes-deploy` does before actually invoking `kubectl` on the rendered YAML. It's also useful for outputting YAML that can be passed to other tools, for validation or introspection purposes.


## Prerequisites

 * `kubernetes-render` does __not__ require a running cluster or an active kubernetes context, which is nice if you want to run it in a CI environment, potentially alongside something like https://github.com/garethr/kubeval to make sure your configuration is sound.
 * Like the other `kubernetes-deploy` commands, `kubernetes-render` requires the `$REVISION` environment variable to be set, and will make it available as `current_sha` in your ERB templates.

## Usage

To render all templates in your template dir, run:

```
kubernetes-render --template-dir=./path/to/template/dir
```

To render some templates in a template dir, run kubernetes-render with the names of the templates to render:

```
kubernetes-render --template-dir=./path/to/template/dir this-template.yaml.erb that-template.yaml.erb
```

*Options:*

- `--template-dir=DIR`: Used to set the directory to interpret template names relative to. This is often the same directory passed as `--template-dir` when running `kubernetes-deploy` to actually deploy templates. Set `$ENVIRONMENT` instead to use `config/deploy/$ENVIRONMENT`.
- `--bindings=BINDINGS`: Makes additional variables available to your ERB templates. For example, `kubernetes-render --bindings=color=blue,size=large some-template.yaml.erb` will expose `color` and `size` to `some-template.yaml.erb`.


# Development

## Setup

If you work for Shopify, just run `dev up`, but otherwise:

1. [Install kubectl version 1.10.0 or higher](https://kubernetes.io/docs/user-guide/prereqs/) and make sure it is in your path
2. [Install minikube](https://kubernetes.io/docs/getting-started-guides/minikube/#installation) (required to run the test suite)
3. Check out the repo
4. Run `bin/setup` to install dependencies

To install this gem onto your local machine, run `bundle exec rake install`.



## Running the test suite locally

Using minikube:

1. Start [minikube](https://kubernetes.io/docs/getting-started-guides/minikube/#installation) (`minikube start [options]`).
2. Make sure you have a context named "minikube" in your kubeconfig. Minikube adds this context for you when you run `minikube start`. You can check for it using `kubectl config get-contexts`.
3. Run `bundle exec rake test` (or `dev test` if you work for Shopify).

Using another local cluster:

1. Start your cluster.
2. Put the name of the context you want to use in a file named `.local-context` in the root of this project. For example: `echo "dind" > .local-context`.
3. Run `bundle exec rake test` (or `dev test` if you work for Shopify).

To make StatsD log what it would have emitted, run a test with `STATSD_DEV=1`.

To see the full-color output of a specific integration test, you can use `PRINT_LOGS=1`. For example: `PRINT_LOGS=1 bundle exec ruby -I test test/integration/kubernetes_deploy_test.rb -n/test_name/`.




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

## Feature acceptance guidelines

- This project's mission is to make it easy to ship changes to a Kubernetes namespace and understand the result. Features that introduce new classes of responsibility to the tool are not usually accepted.
  - Deploys can be a very tempting place to cram features. Imagine a proposed feature actually fits better elsewhere—where might that be? (Examples: validator in CI, custom controller, initializer, pre-processing step in the CD pipeline, or even Kubernetes core)
  - The basic ERB renderer included with the tool is intended as a convenience feature for a better out-of-the box experience. Providing complex rendering capabilities is out of scope of this project's mission, and enhancements in this area may be rejected.
  - The deploy command does not officially support non-namespaced resource types.
- This project strives to be composable with other tools in the ecosystem, such as renderers and validators. The deploy command must work with any Kubernetes templates provided to it, no matter how they were generated.
- This project is open-source. Features tied to any specific organization (including Shopify) will be rejected.
- The deploy command must remain performant when given several hundred resources at a time, generating 1000+ pods. (Technical note: This means only `sync` methods can make calls to the Kuberentes API server during result verification. This both limits the number of API calls made and ensures a consistent view of the world within each polling cycle.)
- This tool must be able to run concurrent deploys to different targets safely, including when used as a library.

## Contributing a new resource type

The list of fully supported types is effectively the list of classes found in `lib/kubernetes-deploy/kubernetes_resource/`.

This gem uses subclasses of `KubernetesResource` to implement custom success/failure detection logic for each resource type. If no subclass exists for a type you're deploying, the gem simply assumes `kubectl apply` succeeded (and prints a warning about this assumption). We're always looking to support more types! Here are the basic steps for contributing a new one:

1. Create a the file for your type in `lib/kubernetes-deploy/kubernetes_resource/`
2. Create a new class that inherits from `KubernetesResource`. Minimally, it should implement the following methods:
    * `sync` -- Gather the data you'll need to determine `deploy_succeeded?` and `deploy_failed?`. The superclass's implementation fetches the corresponding resource, parses it and stores it in `@instance_data`. You can define your own implementation if you need something else.
    * `deploy_succeeded?`
    * `deploy_failed?`
3. Adjust the `TIMEOUT` constant to an appropriate value for this type.
4. Add the a basic example of the type to the hello-cloud [fixture set](https://github.com/Shopify/kubernetes-deploy/tree/master/test/fixtures/hello-cloud) and appropriate assertions to `#assert_all_up` in [`hello_cloud.rb`](https://github.com/Shopify/kubernetes-deploy/blob/master/test/helpers/fixture_sets/hello_cloud.rb). This will get you coverage in several existing tests, such as `test_full_hello_cloud_set_deploy_succeeds`.
5. Add tests for any edge cases you foresee.

## Code of Conduct
Everyone is expected to follow our [Code of Conduct](https://github.com/Shopify/kubernetes-deploy/blob/master/CODE_OF_CONDUCT.md).


# License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
