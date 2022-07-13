require "yaml"

1.times do |nr|
  crd_yaml = {
    "apiVersion" => "apiextensions.k8s.io/v1",
    "kind" => "CustomResourceDefinition",
    "metadata" => {
      "name" => "deploymentss.stable.example.com",
    },
    "spec" => {
      "group" => "stable.example.com",
      "versions" => [
        {
          "name" => "v1",
          "served" => true,
          "storage" => true,
          "schema" => {
            "openAPIV3Schema" => {
              "type" => "object",
              "properties" => {
                "thiny" => {
                  "type" => "string",
                }
              }
            },
          },
        },
      ],
      "scope" => "Cluster",
      "names" => {
        "plural" => "deployments",
        "singular" => "deployment",
        "kind" => "Deployment",
      },
    },
  }

  yaml = YAML.dump(crd_yaml)

  File.write(File.expand_path("crd.yaml", __dir__), yaml)
end
