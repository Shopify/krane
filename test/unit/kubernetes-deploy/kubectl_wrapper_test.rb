require 'test_helper'

class KubectlWrapperTest < KubernetesDeploy::TestCase
  def test_builds_with_namespace
    Open3.expects(:capture3).with('kubectl', 'get', 'pods', '--namespace=trashbin').returns(successful_status)
    out, err, st = KubernetesDeploy::KubectlWrapper.run_kubectl("get", "pods", namespace: "trashbin")
    assert st.success?
  end

  def test_builds_with_context
    Open3.expects(:capture3).with('kubectl', 'get', 'pods', '--context=trashbin').returns(successful_status)
    out, err, st = KubernetesDeploy::KubectlWrapper.run_kubectl("get", "pods", context: "trashbin")
    assert st.success?
  end

  def test_builds_without_context_and_namespace
    Open3.expects(:capture3).with('kubectl', 'get', 'pods').returns(successful_status)
    out, err, st = KubernetesDeploy::KubectlWrapper.run_kubectl("get", "pods")
    assert st.success?
  end

  def test_logs_stderr
    Open3.expects(:capture3).with('kubectl', 'get', 'pods').returns(failed_status_with_stderr)
    out, err, st = KubernetesDeploy::KubectlWrapper.run_kubectl("get", "pods")
    refute st.success?
    assert_logs_match /The following command returned non-zero status/
  end

  private

  FakeProcessStatus = Struct.new(:success?)
  def successful_status
    ["", "", FakeProcessStatus.new(true)]
  end

  def failed_status_with_stderr
    ["", "error", FakeProcessStatus.new(false)]
  end
end
