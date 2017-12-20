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
