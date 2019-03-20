# Contributing to kubernetes-deploy

:+1::tada: First off, thanks for taking the time to contribute! :tada::+1:

The following is a set of guidelines for contributing to kubernetes-deploy. Please take a moment to read through them before submitting your first PR.


#### Table Of Contents

[Code of Conduct](#code-of-conduct)

[What should I know before I get started?](#what-should-i-know-before-i-get-started)
  * [High-level design decisions](#high-level-design-decisions)
  * [Feature acceptance policies](#feature-acceptance-policies)
  * [Adding a new resource type](#contributing-a-new-resource-type)

## Code of Conduct

This project and everyone participating in it are governed by the [Code of Conduct](https://github.com/Shopify/kubernetes-deploy/blob/master/CODE_OF_CONDUCT.md).
By participating, you are expected to uphold this code. Please report unacceptable
behavior to [kubernetes-deploy@shopify.com](mailto:kubernetes-deploy@shopify.com).

## Maintainers

This project is currently under the stewardship of the Production Platform group at Shopify. The two primary maintainers are @knverey and @dturn; their approval is generally required for all significant feature proposals and code architecture changes.

## What should I know before I get started?

### High-level design decisions

**Logging**

Since we are primarily a CLI tool, logging is our entire user interface. Please think carefully about the information you log. Is it clear? Is it logged at the right time? Is it helpful?

In particular, we need to ensure that every mutation we’ve done to the cluster is clearly described (and is something the operator wanted us to do!).

We handle Kubernetes secrets, so it is critical that changes do not cause the contents of any secrets in the template set to be logged.

**Project architecture**

The main interface of this project is our four tasks: `DeployTask`, `RestartTask`, `RunnerTask`, and `RenderTask`. The code in these classes should be high-level abstractions, with implementation details encapsulated in other classes. The public interface of these tasks is a `run` method (and a `run!` equivalent), the body of which should read like a set of phases and steps.

An important design principle of the tasks is that they should try to fail fast before touching the cluster if they will not succeed overall. Part of how we achieve this is by separating each task into phases, where the first phase simply gathers information and runs validations to determine what needs to be done and whether that will be able to succeed. In practice, this is the “Initializing <task>” phase for all tasks, plus the “Checking initial resource statuses” phase for DeployTask. Our users should be able to assume that these initial phases never modify their clusters.

**Thread safety**

This tool must be able to run concurrent deploys to different targets safely, including when used as a library. Each of those deploys will internally also use parallelism via ruby threads, as do our integration tests. This means all of our code must be thread-safe. Notably, our code must not modify the global namespace (e.g. environment variables, classes, class variables or constants), and all gems we depend on must also be thread-safe.

 _Note_: Local tests do not run in parallel by default. To enable it, use `PARALLELIZE_ME=1 PARALLELISM=$NUM_THREADS`. Unit tests never run in parallel because they use mocha, which is not thread-safe (mocha cannot be used in integration tests).

**Performance and the sync cycle**

DeployTask must remain performant when given several hundred resources at a time, generating 1000+ pods. This means only `sync` methods can make calls to the Kubernetes API server during result verification. This both limits the number of API calls made and ensures a consistent view of the world within each polling cycle.



### Feature acceptance policies

**Our mission**

This project's mission is to make it easy to ship changes to a Kubernetes namespace and understand the result. Features that introduce new classes of responsibility to the tool are not usually accepted.

Deploys can be a very tempting place to cram features. Imagine a proposed feature actually fits better elsewhere—where might that be? (Examples: validator in CI, custom controller, initializer, pre-processing step in the CD pipeline, or even Kubernetes core)

**Global resources**

This project is intended to manage a namespace (or a label-delimited subsection of one). It does not officially support non-namespaced resources. In practice, we do model custom resource definitions specifically, because it helps us better handle custom resources (which typically are namespaced). However, our intent is to keep this the only exception to the rule.

**Template rendering**

The basic ERB renderer included with the tool is intended as a convenience feature for a better out-of-the box experience. Providing complex rendering capabilities is outside the scope of this project's mission, and enhancements in this area may be rejected.

**Composability**

This project strives to be composable with other tools in the ecosystem, such as renderers and validators. The deploy task must work with any Kubernetes templates provided to it, no matter how they were generated.

**Universality**

This project is open-source. Features tied to any specific organization (including Shopify) will be rejected.


### Contributing a new resource type

The list of fully supported types is effectively the list of classes found in `lib/kubernetes-deploy/kubernetes_resource/`.

This gem uses subclasses of `KubernetesResource` to implement custom success/failure detection logic for each resource type. If no subclass exists for a type you're deploying, the gem simply assumes `kubectl apply` succeeded (and prints a warning about this assumption). We're always looking to support more types! Here are the basic steps for contributing a new one:

1. Create a file for your type in `lib/kubernetes-deploy/kubernetes_resource/`
2. Create a new class that inherits from `KubernetesResource`. Minimally, it should implement the following methods:
    * `sync` -- Gather the data you'll need to determine `deploy_succeeded?` and `deploy_failed?`. The superclass's implementation fetches the corresponding resource, parses it and stores it in `@instance_data`. You can define your own implementation if you need something else.
    * `deploy_succeeded?`
    * `deploy_failed?`
3. Adjust the `TIMEOUT` constant to an appropriate value for this type.
4. Add the new class to list of resources in
   [`deploy_task.rb`](https://github.com/Shopify/kubernetes-deploy/blob/master/lib/kubernetes-deploy/deploy_task.rb#L8)
5. Add the new resource to the [prune whitelist](https://github.com/Shopify/kubernetes-deploy/blob/master/lib/kubernetes-deploy/deploy_task.rb#L81)
6. Add a basic example of the type to the hello-cloud [fixture set](https://github.com/Shopify/kubernetes-deploy/tree/master/test/fixtures/hello-cloud) and appropriate assertions to `#assert_all_up` in [`hello_cloud.rb`](https://github.com/Shopify/kubernetes-deploy/blob/master/test/helpers/fixture_sets/hello_cloud.rb). This will get you coverage in several existing tests, such as `test_full_hello_cloud_set_deploy_succeeds`.
7. Add tests for any edge cases you foresee.
