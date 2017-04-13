# frozen_string_literal: true
require 'logger'

module KubernetesDeploy
  module Logger
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def logger=(other)
        @logger = other
      end

      def logger
        @logger ||= begin
          l = ::Logger.new($stderr)
          l.level = level_from_env
          l.formatter = proc do |severity, datetime, _progname, msg|
            log_text = "[#{severity}][#{datetime}]\t#{msg}"
            case severity
            when "FATAL" then "\033[0;31m#{log_text}\x1b[0m\n" # red
            when "ERROR", "WARN" then "\033[0;33m#{log_text}\x1b[0m\n" # yellow
            when "INFO" then "\033[0;36m#{log_text}\x1b[0m\n" # blue
            else "#{log_text}\n"
            end
          end
          l
        end
      end

      private

      def level_from_env
        return Logger::DEBUG if ENV["DEBUG"]

        if ENV["LEVEL"]
          Logger.const_get(ENV["LEVEL"].upcase)
        else
          Logger::INFO
        end
      end
    end
  end
end
