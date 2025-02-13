# frozen_string_literal: true

class FullDeployCommand
  DEFAULT_DEPLOY_TIMEOUT = "300s"
  OPTIONS = {
    # Command args
    "command-timeout" => {
      type: :string,
      banner: "duration",
      default: DEFAULT_DEPLOY_TIMEOUT,
      desc: "Max duration to monitor workloads correctly deployed. " \
        "The timeout is applied separately to the global and namespaced deploy steps",
    },
    "filenames" => {
      type: :array,
      banner: "config/deploy/production config/deploy/my-extra-resource.yml",
      aliases: :f,
      required: false,
      default: [],
      desc: "Directories and files that contains the configuration to apply",
    },
    "stdin" => {
      type: :boolean,
      default: false,
      desc: "[DEPRECATED] Read resources from stdin",
    },
    "verbose-log-prefix" => {
      type: :boolean,
      desc: "Add [context][namespace] to the log prefix",
      default: false,
    },

    # Global deploy args
    "global-selector" => {
      type: :string,
      banner: "'label=value'",
      required: true,
      desc: "Select workloads owned by selector(s)",
    },
    "global-selector-as-filter" => {
      type: :boolean,
      desc: "Use --selector as a label filter to deploy only a subset " \
        "of the provided resources",
      default: false,
    },
    "global-prune" => {
      type: :boolean,
      desc: "Enable deletion of resources that match " \
        "the provided selector and do not appear in the provided templates",
      default: true,
    },
    "global-verify-result" => {
      type: :boolean,
      default: true,
      desc: "Verify workloads correctly deployed",
    },

    # Namespaced deploy args
    "protected-namespaces" => {
      type: :array,
      banner: "namespace1 namespace2 namespaceN",
      desc: "Enable deploys to a list of selected namespaces; set to an empty string " \
        "to disable",
      default: PROTECTED_NAMESPACES,
    },
    "prune" => {
      type: :boolean,
      desc: "Enable deletion of resources that do not appear in the template dir",
      default: true,
    },
    "selector-as-filter" => {
      type: :boolean,
      desc: "Use --selector as a label filter to deploy only a subset " \
        "of the provided resources",
      default: false,
    },
    "selector" => {
      type: :string,
      banner: "'label=value'",
      desc: "Select workloads by selector(s)",
    },
    "verify-result" => {
      type: :boolean,
      default: true,
      desc: "Verify workloads correctly deployed",
    },
  }
end
