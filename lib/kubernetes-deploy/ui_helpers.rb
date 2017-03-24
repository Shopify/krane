# frozen_string_literal: true
module KubernetesDeploy
  module UIHelpers
    private

    def phase_heading(phase_name)
      @current_phase ||= 0
      @current_phase += 1
      heading = "Phase #{@current_phase}: #{phase_name}"
      padding = (100.0 - heading.length) / 2
      KubernetesDeploy.logger.info("")
      KubernetesDeploy.logger.info("#{'-' * padding.floor}#{heading}#{'-' * padding.ceil}")
    end

    def log_green(msg)
      KubernetesDeploy.logger.info("\033[0;32m#{msg}\x1b[0m")
    end
  end
end
