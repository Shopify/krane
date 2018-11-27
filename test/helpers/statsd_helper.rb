module StatsDHelper
  extend self
  
  def capture_statsd_calls(&block)
    binding.pry
    mock_backend = ::StatsD::Instrument::Backends::CaptureBackend.new
    old_backend, KubernetesDeploy::StatsD.backend = KubernetesDeploy::StatsD.backend, mock_backend
    block.call
    mock_backend.collected_metrics
  ensure
    if old_backend.kind_of?(::StatsD::Instrument::Backends::CaptureBackend)
      old_backend.collected_metrics.concat(mock_backend.collected_metrics)
    end

    KubernetesDeploy::StatsD.backend = old_backend
  end
end  