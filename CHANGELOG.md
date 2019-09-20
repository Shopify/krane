## next

*Important!*
- The next release will be 1.0.0, which means that master will contain breaking changes.

## 0.28.0

*Enhancements*
- Officially support Kubernetes 1.15 ([#546](https://github.com/Shopify/kubernetes-deploy/pull/546))
- Make sure that we only declare a Service of type LoadBalancer as deployed after its IP address is published. [#547](https://github.com/Shopify/kubernetes-deploy/pull/547)
- Add more validations to `RunnerTask`. [#554](https://github.com/Shopify/kubernetes-deploy/pull/554)
- Validate secrets with `--server-dry-run` on supported clusters. [#553](https://github.com/Shopify/kubernetes-deploy/pull/553) 
*Bug Fixes*
- Fix a bug in rendering where we failed to add a yaml doc separator (`---`) to
  an implicit document if there are multiple documents in the file.
  ([#551](https://github.com/Shopify/kubernetes-deploy/pull/551))

*Other*
- Kubernetes 1.10 is no longer officially supported as of this version ([#546](https://github.com/Shopify/kubernetes-deploy/pull/546))
- We've added a new Krane cli. This code is in alpha. We are providing
no warranty at this time and reserve the right to make major breaking changes including
removing it entirely at any time. ([#256](https://github.com/Shopify/kubernetes-deploy/issues/256))
- Deprecate `kubernetes-deploy.shopify.io` annotations in favour of `krane.shopify.io` ([#539](https://github.com/Shopify/kubernetes-deploy/pull/539))

## 0.27.0

*Enhancements*
- (alpha) Introduce a new `-f` flag for `kubernetes-deploy`. Allows passing in of multiple directories and/or filenames. Currently only usable by `kubernetes-deploy`, not `kubernetes-render`. [#514](https://github.com/Shopify/kubernetes-deploy/pull/514)
- Initial implementation of shared task validation objects. [#533](https://github.com/Shopify/kubernetes-deploy/pull/533)
- Restructure `require`s so that requiring a given task actually gives you the dependencies you need, and doesn't give what you don't need. [#487](https://github.com/Shopify/kubernetes-deploy/pull/487)
- **[Breaking change]** Added ServiceAccount, PodTemplate, ReplicaSet, Role, and RoleBinding to the prune whitelist.
  * To see what resources may be affected, run `kubectl get $RESOURCE -o jsonpath='{ range .items[*] }{.metadata.namespace}{ "\t" }{.metadata.name}{ "\t" }{.metadata.annotations}{ "\n" }{ end }' --all-namespaces | grep "last-applied"`
  * To exclude a resource from kubernetes-deploy (and kubectl apply) management, remove the last-applied annotation `kubectl annotate $RESOURCE $SECRET_NAME kubectl.kubernetes.io/last-applied-configuration-`.

*Bug Fixes*
- StatefulSets with 0 replicas explicitly specified don't fail deploy. [#540](https://github.com/Shopify/kubernetes-deploy/pull/540)
- Search all workloads if a Pod selector doesn't match any workloads when deploying a Service. [#541](https://github.com/Shopify/kubernetes-deploy/pull/541)

*Other*
- `EjsonSecretProvisioner#new` signature has changed. `EjsonSecretProvisioner` objects no longer have access to `kubectl`. Rather, the `ejson-keys` secret used for decryption is now passed in via the calling task. Note that we only consider the `new` and `run(!)` methods of tasks (render, deploy, etc) to have inviolable APIs, so we do not consider this change breaking. [#514](https://github.com/Shopify/kubernetes-deploy/pull/514)

## 0.26.7

*Other*
- Bump `googleauth` dependency. ([#512](https://github.com/Shopify/kubernetes-deploy/pull/512))

## 0.26.6

*Bug Fixes*
- Re-enable support for YAML aliases when using YAML.safe_load [#510](https://github.com/Shopify/kubernetes-deploy/pull/510)

## 0.26.5

*Bug Fixes*
- Support 'volumeBindingMode: WaitForFirstConsumer' condition in StorageClass. [#479](https://github.com/Shopify/kubernetes-deploy/pull/479)
- Fix: Undefined method "merge" on LabelSelector. [#488](https://github.com/Shopify/kubernetes-deploy/pull/488)

*Enhancements*
- Officially support Kubernetes 1.14. [#461](https://github.com/Shopify/kubernetes-deploy/pull/461)
- Allow customising which custom resources are deployed in the pre-deploy phase. [#505](https://github.com/Shopify/kubernetes-deploy/pull/505)

*Other*
- Removes special treatment of GCP authentication by upgrading to `kubeclient` 4.3. [#465](https://github.com/Shopify/kubernetes-deploy/pull/465)

## 0.26.4

*Bug fixes*
- Adds several additional safeguards against the content of Secret resources being logged. [#474](https://github.com/Shopify/kubernetes-deploy/pull/474)

*Enhancements*
- Improves scalability by removing a check that caused recoverable registry problems to fail deploys. [#477](https://github.com/Shopify/kubernetes-deploy/pull/477)

*Other*
- Relaxes our dependency on the OJ gem. [#471](https://github.com/Shopify/kubernetes-deploy/pull/471)

## 0.26.3

*Bug fixes*
- Fixes a bug introduced in 0.26.0 where listing multiple files in the $KUBECONFIG environment variable would throw an error ([#468](https://github.com/Shopify/kubernetes-deploy/pull/468))
- Fixes a bug introduced in 0.26.2 where kubernetes-render started adding YAML headers to empty render results ([#467](https://github.com/Shopify/kubernetes-deploy/pull/467))

## 0.26.2

*Enhancements*
- kubernetes-render outputs results of rendering yml.erb files without passing them
through a yaml parser. ([#454](https://github.com/Shopify/kubernetes-deploy/pull/454))

*Bug fixes*
- Remove use of deprecated feature preventing use with Kubernetes 1.14 ([#460](https://github.com/Shopify/kubernetes-deploy/pull/460))

## 0.26.1

*Bug fixes*
- Fixes a bug where `config/deploy/$ENVIRONMENT` would be used unconditionally if the `ENVIRONMENT` environment variable is set, ignoring any `--template-dir` argument passed.

## 0.26.0

*Enhancements*
- Add support for NetworkPolicies ([#422](https://github.com/Shopify/kubernetes-deploy/pull/422))
- Setting the REVISION environment variable is now optional ([#429](https://github.com/Shopify/kubernetes-deploy/pull/429))
- Defaults KUBECONFIG to `~/.kube/config` ([#429](https://github.com/Shopify/kubernetes-deploy/pull/429))
- Uses `TASK_ID` environment variable as the `deployment_id` when rendering resource templates for better [Shipit](https://github.com/Shopify/shipit) integration. ([#430](https://github.com/Shopify/kubernetes-deploy/pull/430))
- Arguments to `--bindings` will now be deep merged. ([#419](https://github.com/Shopify/kubernetes-deploy/pull/419))
- `kubernetes-deploy` and `kubernetes-render` now support reading templates from STDIN. ([#415](https://github.com/Shopify/kubernetes-deploy/pull/415))
- Support for specifying a `--selector`, a label with which all deployed resources are expected to have, and by which prunable resources will be filtered. This permits sharing a namespace with resources managed by third-parties, including other kubernetes-deploy deployments. ([#439](https://github.com/Shopify/kubernetes-deploy/pull/439))
- Lists of resources printed during deployments will now be sorted alphabetically. ([#441](https://github.com/Shopify/kubernetes-deploy/pull/441))
- Bare / unmanaged pods run as pre-deployment tasks will now stream logs if there is only one of them. ([#436](https://github.com/Shopify/kubernetes-deploy/pull/436))

*Features*

- **[Breaking change]** Support for deploying Secrets from templates ([#424](https://github.com/Shopify/kubernetes-deploy/pull/424)). Non-ejson secrets are now fully supported and therefore **subject to pruning like any other resource**. As a result:
  * If you previously manually `kubectl apply`'d secrets that are not passed to kubernetes-deploy, your first deploy using this version is going to delete them.
  * If you previously passed secrets manifests to kubernetes-deploy and they are no longer in the set you pass to the first deploy using this version, it will delete them.
  * To identify potentially affected secrets in your cluster, run: `kubectl get secrets -o jsonpath='{ range .items[*] }{.metadata.namespace}{ "\t" }{.metadata.name}{ "\t" }{.metadata.annotations}{ "\n" }{ end }' --context=$YOUR_CONTEXT_HERE --all-namespaces | grep -v "kubernetes-deploy.shopify.io/ejson-secret" | grep "last-applied" | cut -f 1,2`. To exclude a secret from kubernetes-deploy (and kubectl apply) management, remove the last-applied annotation `kubectl annotate secret $SECRET_NAME kubectl.kubernetes.io/last-applied-configuration-`.
  * The secret `ejson-keys` will never be pruned by kubernetes-deploy. Instead, it will fail the deploy at the validation stage (unless `--no-prune` is set). ([#447](https://github.com/Shopify/kubernetes-deploy/pull/447))

## 0.25.0

#### WARNING
This version contains an error for handling the `--template-dir` argument. If the `ENVIRONMENT` environment variable is set, the template directory will be forcefully set to `config/deploy/$ENVIRONMENT`. This has been fixed in version 0.26.1

*Features*
- Support timeout overrides on deployments ([#414](https://github.com/Shopify/kubernetes-deploy/pull/414))

*Bug fixes*
- Attempting to deploy from a directory that only contains `secrets.ejson` will no longer fail deploy ([#416](https://github.com/Shopify/kubernetes-deploy/pull/416))
- Remove the risk of sending decrypted EJSON secrets to output([#431](https://github.com/Shopify/kubernetes-deploy/pull/431))

*Other*
- Update kubeclient gem to 4.2.2. Note this replaces the `KubeclientBuilder::GoogleFriendlyConfig` class with `KubeclientBuilder::KubeConfig` ([#418](https://github.com/Shopify/kubernetes-deploy/pull/418)). This resolves [#396](https://github.com/Shopify/kubernetes-deploy/issues/396) and should allow us to support more authentication methods (e.g. `exec` for EKS).
- Invalid context when using `kubernetes-run` gives more descriptive error([#423](https://github.com/Shopify/kubernetes-deploy/pull/423))
- When resources are not found, instead of being `Unknown`, they are now labelled as `Not Found`([#427](https://github.com/Shopify/kubernetes-deploy/pull/427))

## 0.24.0

*Features*
- Add support for specifying pass/fail conditions of Custom Resources ([#376](https://github.com/Shopify/kubernetes-deploy/pull/376)).
- Add support for custom timeouts for Custom Resources([#376](https://github.com/Shopify/kubernetes-deploy/pull/376))

*Enhancements*
- Officially support Kubernetes 1.13 ([#409](https://github.com/Shopify/kubernetes-deploy/pull/409))

*Bug fixes*
- Fixed bug that caused `NameError: wrong constant name` if custom resources had kind with a lowercase first letter. ([#413](https://github.com/Shopify/kubernetes-deploy/pull/413))

*Other*
- Kubernetes 1.9 is no longer officially supported as of this version

## 0.23.0

*Features*
- New command: `kubernetes-render` is a tool for rendering ERB templates to raw Kubernetes YAML. It's useful for seeing what `kubernetes-deploy` does before actually invoking `kubectl` on the rendered YAML. It's also useful for outputting YAML that can be passed to other tools, for validation or introspection purposes. ([#375](https://github.com/Shopify/kubernetes-deploy/pull/375/files))
- **[Breaking change]** This release completes the conversion of `kubernetes-deploy` StatsD metrics to `distribution`s, which was done for `kubernetes-restart` and `kubernetes-run` in v0.22.0.
- Several new distribution metrics are available to give insight into the timing of each step of the deploy process: `KubernetesDeploy.validate_configuration.duration`, `KubernetesDeploy.discover_resources.duration`, `KubernetesDeploy.validate_resources.duration`, `KubernetesDeploy.initial_status.duration`, `KubernetesDeploy.create_ejson_secrets.duration`, `KubernetesDeploy.apply_all.duration`, `KubernetesDeploy.sync.duration`
- **[Breaking change]** `KubernetesDeploy.resource.duration` no longer includes `sha` or `resource` tags. ([#392](https://github.com/Shopify/kubernetes-deploy/pull/392))

*Enhancements*
- Roles are now predeployed before RoleBindings ([#380](https://github.com/Shopify/kubernetes-deploy/pull/380))
- Several performance enhancements for deploys to namespaces with hundreds of resources.
- KubernetesDeploy no longer modifies the global StatsD configuration when used as a gem ([#384](https://github.com/Shopify/kubernetes-deploy/pull/384))

*Bug fixes*
- Handle out-of-order arrival of entries from different streams when processing logs ([#401](https://github.com/Shopify/kubernetes-deploy/pull/401))

## 0.22.0

*Features*
- **[Breaking change]** `kubernetes-restart` now produces StatsD `distribution` instead of `metric`.
Dashboards that used these metrics will need to be updated. ([#374](https://github.com/Shopify/kubernetes-deploy/pull/374))
- `kubernetes-run` now produces StatsD `distribution` to aid in tracking usage ([#374](https://github.com/Shopify/kubernetes-deploy/pull/374))

*Enhancements*
- Predeploy RoleBinding before unmanaged pods ([#354](https://github.com/Shopify/kubernetes-deploy/pull/354))

*Bug Fixes*
- Fixed bug in `kubernetes-restart` that caused "Pod spec does not contain a template
 container called 'task-runner'" error message to not be printed
 ([#371](https://github.com/Shopify/kubernetes-deploy/pull/371))

*Other*
- Kubernetes 1.8 is no longer officially supported as of this version

## 0.21.1

*Enhancements*
- Improved failure detection for job resources. ([#355](https://github.com/Shopify/kubernetes-deploy/pull/355))
- Unmanaged pods are now immediately identified as failed if they are evicted, preempted or deleted out of band. This is especially important to `kubernetes-run`. ([#353](https://github.com/Shopify/kubernetes-deploy/pull/353))

*Other*
- Relaxed our `googleauth` dependency. ([#333](https://github.com/Shopify/kubernetes-deploy/pull/333))

## 0.21.0

*Features*
- **[Breaking change]** `kubernetes-run` now streams container logs and waits for the pod to succeed or fail **by default**. You can disable this using `--skip-wait`, or you can use `--max-watch-seconds=seconds` to set a time limit on the watch. ([#337](https://github.com/Shopify/kubernetes-deploy/pull/337))


*Other*
- Kubernetes 1.7 is no longer officially supported as of this version

## 0.20.6

*Enhancements*
- All resources marked as prunable will now be added to the prune whitelist ([#326](https://github.com/Shopify/kubernetes-deploy/pull/326))
- Improve deploy status detection by ensuring we examine the correct generation ([#325](https://github.com/Shopify/kubernetes-deploy/pull/325))


## 0.20.5
*Enhancements*
- Add Job resource class ([#295](https://github.com/Shopify/kubernetes-deploy/pull/296))
- Add CustomResourceDefinition resource class ([#306](https://github.com/Shopify/kubernetes-deploy/pull/306))
- Officially support Kubernetes 1.10 ([#308](https://github.com/Shopify/kubernetes-deploy/pull/308))
- SyncMediator will only batch fetch resources when there is a sufficiently large enough set of resources
being tracked ([#316](https://github.com/Shopify/kubernetes-deploy/pull/316))
- Allow CRs to be pruned based on `kubernetes-deploy.shopify.io/prunable` annotation on the custom resource definitions ([312](https://github.com/Shopify/kubernetes-deploy/pull/312))
- Add HorizontalPodAutoscaler resource class ([#305](https://github.com/Shopify/kubernetes-deploy/pull/305))

*Bug Fixes*
- Prevent crash when STATSD_IMPLEMENTATION isn't set. ([#3242](https://github.com/Shopify/kubernetes-deploy/pull/324))

### 0.20.4
*Enhancements*
- Don't consider pod preempting a failure ([#317](https://github.com/shopify/kubernetes-deploy/pull/317))

### 0.20.3
*Enhancements*
- Evictions are recoverable so prevent them from triggering fast failure detection ([#293](https://github.com/Shopify/kubernetes-deploy/pull/293)).
- Use YAML.safe_load over YAML.load_file ([#295](https://github.com/Shopify/kubernetes-deploy/pull/295)).

*Bug Fixes*
- Default rollout strategy is compatible required-rollout annotation ([#289](https://github.com/Shopify/kubernetes-deploy/pull/289)).

### 0.20.2
*Enhancements*
- Emit data dog events when deploys succeed, time out or fail ([#292](https://github.com/Shopify/kubernetes-deploy/pull/292)).
### 0.20.1

*Bug Fixes*
- Display a nice error instead of crashing when a YAML document is missing 'Kind'
([#280](https://github.com/Shopify/kubernetes-deploy/pull/280))
- Prevent DaemonSet from succeeding before rollout finishes
  ([#288](https://github.com/Shopify/kubernetes-deploy/issues/288))

*Enhancements*
- Merge multiple `--bindings` arguments, to allow a composite bindings map (multiple arguments or files)

### 0.20.0

*Features*
- Automatically add all Kubernetes namespace labels to StatsD tags ([#278](https://github.com/Shopify/kubernetes-deploy/pull/278))

*Bug Fixes*
- Prevent calling sleep with a negative value ([#273](https://github.com/Shopify/kubernetes-deploy/pull/273))
- Prevent no-op redeploys of bad code from hanging forever ([#262](https://github.com/Shopify/kubernetes-deploy/pull/262))

*Enhancements*
- Improve output for rendering errors ([#253](https://github.com/Shopify/kubernetes-deploy/pull/253))

### 0.19.0
*Features*
- Added `--max-watch-seconds=seconds` to kubernetes-restart and kubernetes-deploy. When set
a timeout error is raised if it takes longer than _seconds_ for any resource to deploy.
- Adds YAML and JSON file reference support to the kubernetes-deploy `--bindings` argument ([#269](https://github.com/Shopify/kubernetes-deploy/pull/269))

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
