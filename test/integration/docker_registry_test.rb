# frozen_string_literal: true
require 'test_helper'

class KubernetesDockerRegistryTest < KubernetesDeploy::IntegrationTest
  def test_we_can_retrieve_image_digests
    digest = image_digest("busybox")
    assert !digest.nil?
    assert_equal digest, image_digest("busybox:latest")
    assert_equal digest, image_digest("library/busybox")
    assert_equal digest, image_digest("library/busybox:latest")
    assert_equal digest, image_digest("registry.hub.docker.com/library/busybox")
    assert_equal digest, image_digest("registry.hub.docker.com/library/busybox:latest")
  end

  def test_we_can_create_image_references_using_digests
    digest = image_digest("busybox")
    assert !digest.nil?
    assert_equal "busybox@#{digest}", image_with_digest("busybox")
    assert_equal "busybox@#{digest}", image_with_digest("busybox:latest")
    assert_equal "busybox@#{digest}", image_with_digest("library/busybox")
    assert_equal "busybox@#{digest}", image_with_digest("library/busybox:latest")
    assert_equal "busybox@#{digest}", image_with_digest("registry.hub.docker.com/library/busybox")
    assert_equal "busybox@#{digest}", image_with_digest("registry.hub.docker.com/library/busybox:latest")
  end

  private

  def image_digest(image)
    KubernetesDeploy::DockerRegistry.image_digest(image)
  end

  def image_with_digest(image)
    KubernetesDeploy::DockerRegistry.image_with_digest(image)
  end
end
