# Contributing to kubernetes-deploy

:+1::tada: First off, thanks for taking the time to contribute! :tada::+1:

The following is a set of guidelines for contributing to kubernetes-deploy.
These are mostly guidelines, not rules. Use your best judgment, and feel free to
propose changes to this document in a pull request.

#### Table Of Contents

[Code of Conduct](#code-of-conduct)

[What should I know before I get started?](#what-should-i-know-before-i-get-started)
  * [Design decisions](#high-level-design-decisions)
  * [Feature acceptance guidelines](#feature-acceptance-guidelines)
  * [Adding a new resource type](#contributing-a-new-resource-type)

## Code of Conduct

This project and everyone participating in it is governed by the [Code of Conduct](https://github.com/Shopify/kubernetes-deploy/blob/master/CODE_OF_CONDUCT.md).
By participating, you are expected to uphold this code. Please report unacceptable
behavior to [kubernetes-deploy@shopify.com](mailto:kubernetes-deploy@shopify.com).

## What should I know before I get started?

### High level design decisions

**Logging**

As a CLI tool logging is our entire user experience. Please think carefully about the information you log. Is it clear? Is it logged at the right time? Is it helpful?

We handle Kubernetes Secrets so it is critical  that changes do not cause the contents of the secret to be logged.

**Runners**

We have four runner tasks: Deploy, Restart, Runner, and Render. The code in these classes should be high level abstractions with implementation details in other classes.

**Global Resources**

Kubernetes-deploy is intended to modify namespaced resources. There is limited support for global resources, ex: CRDs. But a strong use case will be required to support other types.

**Kubernetes-Deploy Task**

This task is broken into 5 phases. We have some
implicit assumptions in each phase.
- Phase 1 & 2 should not modify the state of the cluster.
- Phase 3 & 4 should only modify resources in a way that is expected the operator.

** Parallelism **

Our code and CI has parallelism via ruby threads and this gem is used as a library. Therefore we can not have thread unsafe code. This often happens with  code that modifies the global namespace or gems that are not thread-safe.

 _Note_: Local tests do not run in parallel by default.

### Feature acceptance guidelines

- This project's mission is to make it easy to ship changes to a Kubernetes namespace and understand the result. Features that introduce new classes of responsibility to the tool are not usually accepted.
  - Deploys can be a very tempting place to cram features. Imagine a proposed feature actually fits better elsewhere—where might that be? (Examples: validator in CI, custom controller, initializer, pre-processing step in the CD pipeline, or even Kubernetes core)
  - The basic ERB renderer included with the tool is intended as a convenience feature for a better out-of-the box experience. Providing complex rendering capabilities is out of scope of this project's mission, and enhancements in this area may be rejected.
  - The deploy command does not officially support non-namespaced resource types.
- This project strives to be composable with other tools in the ecosystem, such as renderers and validators. The deploy command must work with any Kubernetes templates provided to it, no matter how they were generated.
- This project is open-source. Features tied to any specific organization (including Shopify) will be rejected.
- The deploy command must remain performant when given several hundred resources at a time, generating 1000+ pods. (Technical note: This means only `sync` methods can make calls to the Kuberentes API server during result verification. This both limits the number of API calls made and ensures a consistent view of the world within each polling cycle.)
- This tool must be able to run concurrent deploys to different targets safely, including when used as a library.

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
6. Add the a basic example of the type to the hello-cloud [fixture set](https://github.com/Shopify/kubernetes-deploy/tree/master/test/fixtures/hello-cloud) and appropriate assertions to `#assert_all_up` in [`hello_cloud.rb`](https://github.com/Shopify/kubernetes-deploy/blob/master/test/helpers/fixture_sets/hello_cloud.rb). This will get you coverage in several existing tests, such as `test_full_hello_cloud_set_deploy_succeeds`.
7. Add tests for any edge cases you foresee.
