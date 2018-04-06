### Unreleased
*Enhancements*
- Prune resource quotas ([#264](https://github.com/Shopify/kubernetes-deploy/pull/264/files))

*Bug Fixes*
- Update gemspec to reflect need for ActiveSupport >= 5.0([#270](https://github.com/Shopify/kubernetes-deploy/pull/270))

### 0.18.1
*Enhancements*
- Change the way the resource watcher fetches resources to make it more efficient for large deploys. Deploys with hundreds of resources are expected to see a measurable performance improvement from this change. ([#251](https://github.com/Shopify/kubernetes-deploy/pull/251))

### 0.18.0
*Features*
- kubernetes-restart and kubernetes-deploy use exit code 70 when a
deploy fails due to one or more resources failing to deploy in time.
([#244](https://github.com/Shopify/kubernetes-deploy/pull/244))

*Bug Fixes*
- Handle deploying thousands of resources at a time, previously kubernetes-deploy would fail with
 `Argument list too long - kubectl (Errno::E2BIG)`. ([#257](https://github.com/Shopify/kubernetes-deploy/pull/257))

### 0.17.0
*Enhancements*

- Add the `--cascade` flag when we force replace a resource. ([#250](https://github.com/Shopify/kubernetes-deploy/pull/250))

### 0.16.0
**Important:** This release changes the officially supported Kubernetes versions to v1.7 through v1.9. Other versions may continue to work, but we are no longer running our test suite against them.

*Features*
- Support partials to reduce duplication in yaml files ([#207](https://github.com/Shopify/kubernetes-deploy/pull/207))

*Bug Fixes*
- Handle podless deamon sets properly ([#242](https://github.com/Shopify/kubernetes-deploy/pull/242))

### 0.15.2
*Enhancements*
- Print warnings if kubernetes server version is not supported ([#237](https://github.com/Shopify/kubernetes-deploy/pull/237)).
- Possible via env var to disable fetching logs and/or events on deployment failure ([#239](https://github.com/Shopify/kubernetes-deploy/pull/239)).
- The `kubernetes-deploy.shopify.io/required-rollout` annotation now takes a percent (e.g. 90%) ([#240](https://github.com/Shopify/kubernetes-deploy/pull/240)).

### 0.15.1
*Enhancements*
- Fetch debug events and logs for failed resources in parallel ([#238](https://github.com/Shopify/kubernetes-deploy/pull/238))

### 0.15.0
*Bug Fixes*
- None

*Enhancements*
- Support for cronjob resource ([#206](https://github.com/Shopify/kubernetes-deploy/pull/206])).
- Make it possible to override the tool's hard timeout for one specific resource via the `kubernetes-deploy.shopify.io/timeout-override`
annotation ([#232](https://github.com/Shopify/kubernetes-deploy/pull/232)).
- Make it possible to modify how many replicas need to be updated and available before a deployment is considered
successful via the `kubernetes-deploy.shopify.io/required-rollout` annotation ([#208](https://github.com/Shopify/kubernetes-deploy/pull/208)).

### 0.14.1
*Bug Fixes*
- Make deployments whose pods crash because of CreateContainerConfigError fail fast in 1.8+ too (they would previously time out).
- Fix crashes when deploying ExternalName services or services without selectors ([#211](https://github.com/Shopify/kubernetes-deploy/pull/211))
- Predeploy ServiceAccount resources ([#221](https://github.com/Shopify/kubernetes-deploy/pull/221))

*Enhancements*
- Make it possible to pass bindings (via the --bindings flag) for which the value contains commas or is a JSON encoded hash ([#219](https://github.com/Shopify/kubernetes-deploy/pull/219))
- Support KUBECONFIG referencing multiple files ([#222](https://github.com/Shopify/kubernetes-deploy/pull/222))

### 0.14.0
*Bug Fixes*
- Fix incorrect timeouts occasionally observed on deployments using progressDeadlineSeconds in Kubernetes <1.7.7

*Enhancements*
- Renamed `KubernetesDeploy::Runner` (which powers `exe/kubernetes-deploy`) to `KubernetesDeploy::DeployTask`. This increases consistency between our primary class names and avoids confusion with `KubernetesDeploy::RunnerTask` (which powers `exe/kubernetes-run`).
- Improved output related to timeouts. For deployments, both failure and timeout output now mentions the referenced replica set.
- Small improvements to the reliability of the success polling.
- EjsonSecretProvisioner no longer logs kubectl command output (which may contain secret data) when debug-level logging is enabled.

### 0.13.0
*Features*
- Added support for StatefulSets for kubernetes 1.7+ using RollingUpdate

*Bug Fixes*
- Explicitly require the minimum rest-client version required by kubeclient ([#202](https://github.com/Shopify/kubernetes-deploy/pull/202))

*Enhancements*
- Begin official support for Kubernetes v1.8 ([#198](https://github.com/Shopify/kubernetes-deploy/pull/198), [#200](https://github.com/Shopify/kubernetes-deploy/pull/200))

### 0.12.12
*Bug Fixes*
- Fix an issue deploying Shopify's internal custom resources.

### 0.12.11
*Bug Fixes*
- Stop appending newlines to the base64-encoded values of secrets created from ejson. These extra newlines were preventing the ejson->k8s secret feature from working with v1.8 (https://github.com/Shopify/kubernetes-deploy/pull/196).

### 0.12.10
*Enhancement*
- Log reason if deploy times out due to `progressDeadlineSeconds` being exceeded

### 0.12.9
*Bug Fixes*
- Retry discovering namespace and kubernetes context
- Expose real error during namespace discovery

### 0.12.8
*Bug Fixes*
- Force deployment to use its own hard timeout instead of relying on the replica set
