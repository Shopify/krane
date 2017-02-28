require 'test_helper'

class KubernetesResourceTest < KubernetesDeploy::TestCase
  def test_service_and_deployment_timeouts_are_equal
    message = "Service and Deployment timeouts have to match since services are waiting to get endpoints from their backing deployments"
    assert_equal KubernetesDeploy::Service.timeout, KubernetesDeploy::Deployment.timeout, message
  end
end
