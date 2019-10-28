# frozen_string_literal: true
module StatsDHelper
  def capture_statsd_calls
    mock_backend = ::StatsD::Instrument::Backends::CaptureBackend.new
    old_backend = Krane::StatsD.backend
    Krane::StatsD.backend = mock_backend

    yield if block_given?

    mock_backend.collected_metrics
  ensure
    if old_backend.is_a?(::StatsD::Instrument::Backends::CaptureBackend)
      old_backend.collected_metrics.concat(mock_backend.collected_metrics)
    end
    Krane::StatsD.backend = old_backend
  end
end
