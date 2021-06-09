# krane [![Build status](https://badge.buildkite.com/35c56e797c3bbd6ba50053aefdded0715898cd8e8c86f7e462.svg?branch=master)](https://buildkite.com/shopify/krane)

> This project used to be called `kubernetes-deploy`. Check out our [migration guide](https://github.com/Shopify/krane/blob/master/1.0-Upgrade.md) for more information including details about breaking changes.


`krane` is a command line tool that helps you ship changes to a Kubernetes namespace and understand the result. At Shopify, we use it within our much-beloved, open-source [Shipit](https://github.com/Shopify/shipit-engine#kubernetes) deployment app.

Why not just use the standard `kubectl apply` mechanism to deploy? It is indeed a fantastic tool; `krane` uses it under the hood! However, it leaves its users with some burning questions: _What just happened?_ _Did it work?_

Especially in a CI/CD environment, we need a clear, actionable pass/fail result for each deploy. Providing this was the foundational goal of `krane`, which has grown to support the following core features:

​:eyes:  Watches the changes you requested to make sure they roll out successfully.

:interrobang: Provides debug information for changes that failed.

:1234:  Predeploys certain types of resources (e.g. ConfigMap, PersistentVolumeClaim) to make sure the latest version will be available when resources that might consume them (e.g. Deployment) are deployed.

:closed_lock_with_key:  [Creates Kubernetes secrets from encrypted EJSON](#deploying-kubernetes-secrets-from-ejson), which you can safely commit to your repository

​:running: [Running tasks at the beginning of a deploy](#running-tasks-at-the-beginning-of-a-deploy) using bare pods (example use case: Rails migrations)

If you need the ability to render dynamic values in templates before deploying, you can use [krane render](#krane-render). Alongside that, this repo also includes tools for [running tasks](#krane-run) and [restarting deployments](#krane-restart).



![demo-deploy.gif](screenshots/deploy-demo.gif)



![missing-secret-fail](screenshots/missing-secret-fail.png)


--------



## Table of contents

**KRANE DEPLOY**
* [Prerequisites](#prerequisites)
* [Installation](#installation)
* [Usage](#usage)
  * [Using templates](#using-templates)
  * [Customizing behaviour with annotations](#customizing-behaviour-with-annotations)
  * [Running tasks at the beginning of a deploy](#running-tasks-at-the-beginning-of-a-deploy)
  * [Deploying Kubernetes secrets (from EJSON)](#deploying-kubernetes-secrets-from-ejson)
  * [Deploying custom resources](#deploying-custom-resources)
* [Walk through the steps of a deployment](#deploy-walkthrough)

**KRANE GLOBAL DEPLOY**
* [Usage](#usage-1)

**KRANE RESTART**
* [Usage](#usage-2)

**KRANE RUN**
* [Prerequisites](#prerequisites-1)
* [Usage](#usage-3)

**KRANE RENDER**
* [Prerequisites](#prerequisites-2)
* [Usage](#usage-4)

**CONTRIBUTING**
* [Contributing](#contributing)
* [Code of Conduct](#code-of-conduct)
* [License](#license)


----------



## Prerequisites

* Ruby 2.6+
* Your cluster must be running Kubernetes v1.15.0 or higher<sup>1</sup>

<sup>1</sup> We run integration tests against these Kubernetes versions. You can find our
official compatibility chart below.

| Kubernetes version | Last officially supported in gem version |
| :----------------: | :-------------------: |
|        1.5         |        0.11.2         |
|        1.6         |        0.15.2         |
|        1.7         |        0.20.6         |
|        1.8         |        0.21.1         |
|        1.9         |        0.24.0         |
|        1.10        |        0.27.0         |

## Installation

1. [Install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-binary-via-curl) (requires v1.15.0 or higher) and make sure it is available in your $PATH
2. Set up your [kubeconfig file](https://kubernetes.io/docs/tasks/access-application-cluster/authenticate-across-clusters-kubeconfig/) for access to your cluster(s).
3. `gem install krane`




## Usage

`krane deploy <app's namespace> <kube context>`

*Environment variables:*

- `$KUBECONFIG`: points to one or multiple valid kubeconfig files that include the context you want to deploy to. File names are separated by colon for Linux and Mac, and semi-colon for Windows. If omitted, Krane will use the Kubernetes default of `~/.kube/config`.
- `$GOOGLE_APPLICATION_CREDENTIALS`: points to the credentials for an authenticated service account (required if your kubeconfig `user`'s auth provider is GCP)


*Options:*

Refer to `krane help` for the authoritative set of options.


- `--filenames / -f [PATHS]`: Accepts a list of directories and/or filenames to specify the set of directories/files that will be deployed, use `-` to specify reading from STDIN.
- `--no-prune`: Skips pruning of resources that are no longer in your Kubernetes template set. Not recommended, as it allows your namespace to accumulate cruft that is not reflected in your deploy directory.
- `--global-timeout=duration`: Raise a timeout error if it takes longer than _duration_ for any
resource to deploy.
- `--selector`: Instructs krane to only prune resources which match the specified label selector, such as `environment=staging`. If you use this option, all resource templates must specify matching labels. See [Sharing a namespace](#sharing-a-namespace) below.
- `--selector-as-filter`: Instructs krane to only deploy resources that are filtered by the specified labels in `--selector`. The deploy will not fail if not all resources match the labels. This is useful if you only want to deploy a subset of resources within a given YAML file. See [Sharing a namespace](#sharing-a-namespace) below.
- `--no-verify-result`: Skip verification that workloads correctly deployed.
- `--protected-namespaces=default kube-system kube-public`: Fail validation if a deploy is targeted at a protected namespace.
- `--verbose-log-prefix`: Add [context][namespace] to the log prefix


> **NOTICE**: Deploy Secret resources at your own risk. Although we will fix any reported leak vectors with urgency, we cannot guarantee that sensitive information will never be logged.

### Sharing a namespace

By default, krane will prune any resources in the target namespace which have the `kubectl.kubernetes.io/last-applied-configuration` annotation and are not a result of the current deployment process, on the assumption that there is a one-to-one relationship between application deployment and namespace, and that a deployment provisions all relevant resources in the namespace.

If you need to, you may specify `--no-prune` to disable all pruning behaviour, but this is not recommended.

If you need to share a namespace with resources which are managed by other tools or indeed other krane deployments, you can supply the `--selector` option, such that only resources with labels matching the selector are considered for pruning.

If you need to share a namespace with different set of resources using the same YAML file, you can supply the `--selector` and `--selector-as-filter` options, such that only the resources that match with the labels will be deployed. In each run of deploy, you can use different labels in `--selector` to deploy a different set of resources. Only the deployed resources in each run are considered for pruning.

### Using templates

All templates must be YAML formatted.
We recommended storing each app's templates in a single directory, `{app root}/config/deploy/{env}`. However, you may use multiple directories.

If you want dynamic templates, you may render ERB with `krane render` and then pipe that result to `krane deploy -f -`.

### Customizing behaviour with annotations
- `krane.shopify.io/timeout-override`: Override the tool's hard timeout for one specific resource. Both full ISO8601 durations and the time portion of ISO8601 durations are valid. Value must be between 1 second and 24 hours.
  - _Example values_: 45s / 3m / 1h / PT0.25H
  - _Compatibility_: all resource types
- `krane.shopify.io/required-rollout`: Modifies how much of the rollout needs to finish
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
- `krane.shopify.io/predeployed`: Causes a Custom Resource to be deployed in the pre-deploy phase.
  - _Compatibility_: Custom Resource Definition
  - _Default_: `true`
  - `true`: The custom resource will be deployed in the pre-deploy phase.
  - All other values: The custom resource will be deployed in the main deployment phase.
- `krane.shopify.io/deploy-method-override`: Cause a resource to be deployed by the specified `kubectl` command, instead of the default `apply`.
  - _Compatibility_: Cannot be used for `PodDisruptionBudget`, since it always uses `create/replace-force`
  - _Accepted values_: `create`, `replace`, and `replace-force`
  - _Warning_: Resources whose deploy method is overridden are no longer subject to pruning on deploy.
  - This feature is _experimental_ and may be removed at any time.


### Running tasks at the beginning of a deploy

To run a task in your cluster at the beginning of every deploy, simply include a `Pod` template in your deploy directory. `krane` will first deploy any `ConfigMap` and `PersistentVolumeClaim` resources present in the provided templates, followed by any such pods. If the command run by one of these pods fails (i.e. exits with a non-zero status), the overall deploy will fail at this step (no other resources will be deployed).

*Requirements:*

* The pod's name should include `<%= deployment_id %>` to ensure that a unique name will be used on every deploy (the deploy will fail if a pod with the same name already exists).
* The pod's `spec.restartPolicy` must be set to `Never` so that it will be run exactly once. We'll fail the deploy if that run exits with a non-zero status.
* The pod's `spec.activeDeadlineSeconds` should be set to a reasonable value for the performed task (not required, but highly recommended)

A simple example can be found in the test fixtures: [test/fixtures/hello-cloud/unmanaged-pod-1.yml.erb](test/fixtures/hello-cloud/unmanaged-pod-1.yml.erb).

The logs of all pods run in this way will be printed inline. If there is only one pod, the logs will be streamed in real-time. If there are multiple, they will be fetched when the pod terminates.

![migrate-logs](screenshots/migrate-logs.png)



### Deploying Kubernetes secrets (from EJSON)

**Note: If you're a Shopify employee using our cloud platform, this setup has already been done for you. Please consult the CloudPlatform User Guide for usage instructions.**

Since their data is only base64 encoded, Kubernetes secrets should not be committed to your repository. Instead, `krane` supports generating secrets from an encrypted [ejson](https://github.com/Shopify/ejson) file in your template directory. Here's how to use this feature:

1. Install the ejson gem: `gem install ejson`
2. Generate a new keypair: `ejson keygen` (prints the keypair to stdout)
3. Create a Kubernetes secret in your target namespace with the new keypair: `kubectl create secret generic ejson-keys --from-literal=YOUR_PUBLIC_KEY=YOUR_PRIVATE_KEY --namespace=TARGET_NAMESPACE`
>Warning: Do *not* use `apply` to create the `ejson-keys` secret. krane will fail if `ejson-keys` is prunable. This safeguard is to protect against the accidental deletion of your private keys.
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
7. Commit the encrypted file and deploy. The deploy will create secrets from the data in the `kubernetes_secrets` key. The ejson file must be included in the resources passed to `--filenames` it can not be read through stdin.

**Note**: Since leading underscores in ejson keys are used to skip encryption of the associated value, `krane` will strip these leading underscores when it creates the keys for the Kubernetes secret data. For example, given the ejson data below, the `monitoring-token` secret will have keys `api-token` and `property` (_not_ `_property`):

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

**A warning about using EJSON secrets with `--selector`**: when using EJSON to generate `Secret` resources and specifying a `--selector` for deployment, the labels from the selector are automatically added to the `Secret`. If _the same_ EJSON file is deployed to the same namespace using different selectors, this will cause the resource to thrash - even if the contents of the secret were the same, the resource has different labels on each deploy.

### Deploying custom resources

By default, krane does not check the status of custom resources; it simply assumes that they deployed successfully. In order to meaningfully monitor the rollout of custom resources, krane supports configuring pass/fail conditions using annotations on CustomResourceDefinitions (CRDs).

*Requirements:*

* The custom resource must expose a `status` subresource with an `observedGeneration` field.
* The `krane.shopify.io/instance-rollout-conditions` annotation must be present on the CRD that defines the custom resource.
* (optional) The `krane.shopify.io/instance-timeout` annotation can be added to the CRD that defines the custom resource to override the global default timeout for all instances of that resource. This annotation can use ISO8601 format or unprefixed ISO8601 time components (e.g. '1H', '60S').

#### Specifying pass/fail conditions

The presence of a valid `krane.shopify.io/instance-rollout-conditions` annotation on a CRD will cause krane to monitor the rollout of all instances of that custom resource. Its value can either be `"true"` (giving you the defaults described in the next section) or a valid JSON string with the following format:
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

For all conditions, `path` must be a valid JsonPath expression that points to a field in the custom resource's status. `value` is the value that must be present at `path` in order to fulfill a condition. For a deployment to be successful, _all_ `success_conditions` must be fulfilled. Conversely, the deploy will be marked as failed if _any one of_ `failure_conditions` is fulfilled. `success_conditions` are mandatory, but `failure_conditions` can be omitted (the resource will simply time out if it never reaches a successful state).

In addition to `path` and `value`, a failure condition can also contain `error_msg_path` or `custom_error_msg`. `error_msg_path` is a JsonPath expression that points to a field you want to surface when a failure condition is fulfilled. For example, a status condition may expose a `message` field that contains a description of the problem it encountered. `custom_error_msg` is a string that can be used if your custom resource doesn't contain sufficient information to warrant using `error_msg_path`. Note that `custom_error_msg` has higher precedence than `error_msg_path` so it will be used in favor of `error_msg_path` when both fields are present.

**Warning:**

You **must** ensure that your custom resource controller sets `.status.observedGeneration` to match the observed `.metadata.generation` of the monitored resource once its sync is complete. If this does not happen, krane will not check success or failure conditions and the deploy will time out.

#### Example

As an example, the following is the default configuration that will be used if you set `krane.shopify.io/instance-rollout-conditions: "true"` on the CRD that defines the custom resources you wish to monitor:

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

The paths defined here are based on the [typical status properties](https://github.com/kubernetes/community/blob/master/contributors/devel/api-conventions.md#typical-status-properties) as defined by the Kubernetes community. It expects the `status` subresource to contain a `conditions` array whose entries minimally specify `type`, `status`, and `message` fields.

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
    reason: "exampleFailed"
    message: "resource is failed"
```

- `observedGeneration == metadata.generation`, so krane will check this resource's success and failure conditions.
- Since `$.status.conditions[?(@.type == "Ready")].status == "False"`, the resource is not considered successful yet.
- `$.status.conditions[?(@.type == "Failed")].status == "True"` means that a failure condition has been fulfilled and the resource is considered failed.
- Since `error_msg_path` is specified, krane will log the contents of `$.status.conditions[?(@.type == "Failed")].message`, which in this case is: `resource is failed`.

### Deploy walkthrough

Let's walk through what happens when you run the `deploy` task with [this directory of templates](https://github.com/Shopify/krane/tree/master/test/fixtures/hello-cloud). This particular example uses ERB templates as well, so we'll use the [krane render](#krane-render) task to achieve that.

You can test this out for yourself by running the following command:

```bash
krane render -f test/fixtures/hello-cloud --current-sha 1 | krane deploy my-namespace my-k8s-cluster -f -
```

As soon as you run this, you'll start seeing some output being streamed to STDERR.

#### Phase 1: Initializing deploy

In this phase, we:

- Perform basic validation to ensure we can proceed with the deploy. This includes checking if we can reach the context, if the context is valid, if the namespace exists within the context, and more. We try to validate as much as we can before trying to ship something because we want to avoid having an incomplete deploy in case of a failure (this is especially important because there's no rollback support).
- List out all the resources we want to deploy (as described in the template files we used).

#### Phase 2: Checking initial resource statuses

In this phase, we check resource statuses. For each resource listed in the previous step, we check Kubernetes for their status; in the first deploy this might show a bunch of items as "Not Found", but for the deploy of a new version, this is an example of what it could look like:

```
Certificate/services-foo-tls     Exists
Cloudsql/foo-production          Provisioned
Deployment/jobs                  3 replicas, 3 updatedReplicas, 3 availableReplicas
Deployment/web                   3 replicas, 3 updatedReplicas, 3 availableReplicas
Ingress/web                      Created
Memcached/foo-production         Healthy
Pod/db-migrate-856359            Unknown
Pod/upload-assets-856359         Unknown
Redis/foo-production             Healthy
Service/web                      Selects at least 1 pod
```

The next phase might be either "Predeploying priority resources" (if there's any) or "Deploying all resources". In this example we'll go through the former, as we do have predeployable resources.

#### Phase 3: Predeploying priority resources

This is the first phase that could modify the cluster.

In this phase we predeploy certain types of resources (e.g. `ConfigMap`, `PersistentVolumeClaim`, `Secret`, ...) to make sure the latest version will be available when resources that might consume them (e.g. `Deployment`) are deployed. This phase will be skipped if the templates don't include any resources that would need to be predeployed.

When this runs, we essentially run `kubectl apply` on those templates and periodically check the cluster for the current status of each resource so we can display error or success information. This will look different depending on the type of resource. If you're running the command described above, you should see something like this in the output:

```
Deploying ConfigMap/hello-cloud-configmap-data (timeout: 30s)
Successfully deployed in 0.2s: ConfigMap/hello-cloud-configmap-data

Deploying PersistentVolumeClaim/hello-cloud-redis (timeout: 300s)
Successfully deployed in 3.3s: PersistentVolumeClaim/hello-cloud-redis

Deploying Role/role (timeout: 300s)
Don't know how to monitor resources of type Role. Assuming Role/role deployed successfully.
Successfully deployed in 0.2s: Role/role
```

As you can see, different types of resources might have different timeout values and different success criteria; in some specific cases (such as with Role) we might not know how to confirm success or failure, so we use a higher timeout value and assume it did work.

#### Phase 4: Deploying all resources

In this phase, we:

- Deploy all resources found in the templates, including resources that were predeployed in the previous step (which should be treated as a no-op by Kubernetes). We deploy everything so the pruning logic (described below) doesn't remove any predeployed resources.
- Prune resources not found in the templates (you can disable this by using `--no-prune`).

Just like in the previous phase, we essentially run `kubectl apply` on those templates and periodically check the cluster for the current status of each resource so we can display error or success information.

If pruning is enabled (which, again, is the default), any [kind not listed in the blacklist](https://github.com/Shopify/krane/blob/master/lib/krane/cluster_resource_discovery.rb#L20) that we can find in the namespace but not in the templates will be removed. A particular message about pruning will be printed in the next phase if any resource matches this criteria.

#### Result

The result section will show:
- A global status: if **all** resources were deployed successfully, this will show up as "SUCCESS"; if at least one resource failed to deploy (due to an error or timeout), this will show up as "FAILURE".
- A list of resources and their individual status: this will show up as something like "Available", "Created", and "1 replica, 1 availableReplica, 1 readyReplica".

At this point the command also returns a status code:
- If it was a success, `0`
- If there was a timeout, `70`
- If any other failure happened, `1`

**On timeouts**: It's important to notice that a single resource timeout or a global deploy timeout doesn't necessarily mean that the operation failed. Since Kubernetes updates are asynchronous, maybe something was just too slow to return in the configured time; in those cases, usually running the deploy again might work (that should be a no-op for most - if not all - resources).

# krane global deploy

Ship non-namespaced resources to a cluster

krane global-deploy (accessible through the Ruby API as Krane::GlobalDeployTask) can deploy global (non-namespaced) resources such as PersistentVolume, Namespace, and CustomResourceDefinition.
Its interface is very similar to krane deploy.

## Usage

`krane global-deploy <kube context>`

```bash
$ cat my-template.yml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: testing-storage-class
      labels:
        app: krane
    provisioner: kubernetes.io/no-provisioner

$ krane global-deploy my-k8s-context -f my-template.yml --selector app=krane
```

*Options:*

Refer to `krane global-deploy help` for the authoritative set of options.

- `--filenames / -f [PATHS]`: Accepts a list of directories and/or filenames to specify the set of directories/files that will be deployed. Use `-` to specify STDIN.
- `--no-prune`: Skips pruning of resources that are no longer in your Kubernetes template set. Not recommended, as it allows your namespace to accumulate cruft that is not reflected in your deploy directory.
- `--selector`: Instructs krane to only prune resources which match the specified label selector, such as `environment=staging`. By using this option, all resource templates must specify matching labels. See [Sharing a namespace](#sharing-a-namespace) below.
- `--selector-as-filter`: Instructs krane to only deploy resources that are filtered by the specified labels in `--selector`. The deploy will not fail if not all resources match the labels. This is useful if you only want to deploy a subset of resources within a given YAML file. See [Sharing a namespace](#sharing-a-namespace) below.
- `--global-timeout=duration`: Raise a timeout error if it takes longer than _duration_ for any
resource to deploy.
- `--no-verify-result`: Skip verification that resources correctly deployed.

# krane restart

`krane restart` is a tool for restarting all of the pods in one or more deployments. It triggers the restart by touching the `RESTARTED_AT` environment variable in the deployment's podSpec. The rollout strategy defined for each deployment will be respected by the restart.

## Usage

**Option 1: Specify the deployments you want to restart**

The following command will restart all pods in the `web` and `jobs` deployments:

`krane restart <kube namespace> <kube context> --deployments=web jobs`


**Option 2: Annotate the deployments you want to restart**

Add the annotation `shipit.shopify.io/restart` to all the deployments you want to target, like this:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  annotations:
    shipit.shopify.io/restart: "true"
```

With this done, you can use the following command to restart all of them:

`krane restart <kube namespace> <kube context>`

*Options:*

Refer to `krane help restart` for the authoritative set of options.

- `--selector`: Only restarts Deployments which match the specified Kubernetes resource selector.
- `--deployments`: Restart specific Deployment resources by name.
- `--global-timeout=duration`: Raise a timeout error if it takes longer than _duration_ for any
resource to restart.
- `--no-verify-result`: Skip verification that workloads correctly restarted.

# krane run

`krane run` is a tool for triggering a one-off job, such as a rake task, _outside_ of a deploy.



## Prerequisites

* You've already deployed a [`PodTemplate`](https://v1-15.docs.kubernetes.io/docs/reference/generated/kubernetes-api/v1.15/#podtemplate-v1-core) object with field `template` containing a `Pod` specification that does not include the `apiVersion` or `kind` parameters. An example is provided in this repo in `test/fixtures/hello-cloud/template-runner.yml`.
* The `Pod` specification in that template has a container named `task-runner`.

Based on this specification `krane run` will create a new pod with the entrypoint of the `task-runner ` container overridden with the supplied arguments.



## Usage

`krane run <kube namespace> <kube context> --arguments=<arguments> --command=<command> --template=<template name>`

*Options:*

* `--template=TEMPLATE`: Specifies the name of the PodTemplate to use.
* `--env-vars=ENV_VARS`: Accepts a list of environment variables to be added to the pod template. For example, `--env-vars="ENV=VAL ENV2=VAL2"` will make `ENV` and `ENV2` available to the container.
* `--command=`: Override the default command in the container image.
* `--no-verify-result`: Skip verification of pod success
* `--global-timeout=duration`: Raise a timeout error if the pod runs for longer than the specified duration
* `--arguments:`: Override the default arguments for the command with a space-separated list of arguments


# krane render

`krane render` is a tool for rendering ERB templates to raw Kubernetes YAML. It's useful for outputting YAML that can be passed to other tools, for validation or introspection purposes.


## Prerequisites

 * `krane render` does __not__ require a running cluster or an active kubernetes context, which is nice if you want to run it in a CI environment, potentially alongside something like https://github.com/garethr/kubeval to make sure your configuration is sound.

## Usage

To render all templates in your template dir, run:

```
krane render -f ./path/to/template/dir
```

To render some templates in a template dir, run krane render with the names of the templates to render:

```
krane render -f ./path/to/template/dir/this-template.yaml.erb
```

To render a template in a template dir and output it to a file, run krane render with the name of the template and redirect the output to a file:

```
krane render -f ./path/to/template/dir/template.yaml.erb > template.yaml
```

*Options:*

- `--filenames / -f [PATHS]`: Accepts a list of directories and/or filenames to specify the set of directories/files that will be deployed. Use `-` to specify STDIN.
- `--bindings=BINDINGS`: Makes additional variables available to your ERB templates. For example, `krane render --bindings=color=blue size=large -f some-template.yaml.erb` will expose `color` and `size` to `some-template.yaml.erb`.
- `--current-sha`: Expose SHA `current_sha` in ERB bindings

You can add additional variables using the `--bindings=BINDINGS` option which can be formatted as a string, JSON string or path to a JSON or YAML file. Complex JSON or YAML data will be converted to a Hash for use in templates. To load a file, the argument should include the relative file path prefixed with an `@` sign. An argument error will be raised if the string argument cannot be parsed, the referenced file does not include a valid extension (`.json`, `.yaml` or `.yml`) or the referenced file does not exist.

#### Bindings examples

```
# Comma separated string. Exposes, 'color' and 'size'
$ krane render --bindings=color=blue,size=large

# JSON string. Exposes, 'color' and 'size'
$ krane render --bindings='{"color":"blue","size":"large"}'

# Load JSON file from ./config
$ krane render --bindings='@config/production.json'

# Load YAML file from ./config (.yaml or yml supported)
$ krane render --bindings='@config/production.yaml'

# Load multiple files via a space separated string
$ krane render --bindings='@config/production.yaml' '@config/common.yaml'
```

#### Using partials

`krane` supports composing templates from so called partials in order to reduce duplication in Kubernetes YAML files. Given a directory `DIR`, partials are searched for in `DIR/partials`and in 'DIR/../partials', in that order. They can be embedded in other ERB templates using the helper method `partial`. For example, let's assume an application needs a number of different CronJob resources, one could place a template called `cron` in one of those directories and then use it in the main deployment.yaml.erb like so:

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

but you can do:

```yaml
<<: <%= partial 'p' %>
x: yz
```

This is a limitation of the current implementation.

# Contributing

We :heart: contributors! To make it easier for you and us we've written a
[Contributing Guide](https://github.com/Shopify/krane/blob/master/CONTRIBUTING.md)


You can also reach out to us on our slack channel, #krane, at https://kubernetes.slack.com. All are welcome!

## Code of Conduct
Everyone is expected to follow our [Code of Conduct](https://github.com/Shopify/krane/blob/master/CODE_OF_CONDUCT.md).


# License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
