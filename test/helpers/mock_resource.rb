# frozen_string_literal: true

MockResource = Struct.new(:id, :hits_to_complete, :status) do
  self::SYNC_DEPENDENCIES = []
  self::SENSITIVE_TEMPLATE_CONTENT = false

  def debug_message(*)
    @debug_message
  end

  def sync(_cache)
    @hits ||= 0
    @hits += 1
  end

  def after_sync
  end

  def type
    "MockResource"
  end
  alias_method :kubectl_resource_type, :type

  def pretty_timeout_type
  end

  def deploy_method
    :apply
  end

  def file_path
    "/dev/null"
  end

  def deploy_started_at=(_)
  end

  def sensitive_template_content?
    true
  end

  def global?
    false
  end

  def deploy_succeeded?
    status == "success" && hits_complete?
  end

  def deploy_failed?
    status == "failed" && hits_complete?
  end

  def deploy_timed_out?
    status == "timeout" && hits_complete?
  end

  def timeout
    hits_to_complete
  end

  def sync_debug_info(_)
    @debug_message = "Something went wrong"
  end

  def pretty_status
    "#{id}  #{status} (#{@hits} hits)"
  end

  def report_status_to_statsd(watch_time)
  end

  private

  def hits_complete?
    @hits ||= 0
    @hits >= hits_to_complete
  end
end
