# frozen_string_literal: true
require 'logger'
require 'kubernetes-deploy/deferred_summary_logging'

module KubernetesDeploy
  class FormattedLogger < Logger
    include DeferredSummaryLogging

    def self.build(namespace, context, stream = $stderr, verbose_prefix: false)
      l = new(stream)
      l.level = level_from_env

      l.formatter = proc do |severity, datetime, _progname, msg|
        middle = verbose_prefix ? "[#{context}][#{namespace}]" : ""
        colorized_line = ColorizedString.new("[#{severity}][#{datetime}]#{middle}\t#{msg}\n")

        case severity
        when "FATAL"
          ColorizedString.new("[#{severity}][#{datetime}]#{middle}\t").red + "#{msg}\n"
        when "ERROR"
          colorized_line.red
        when "WARN"
          colorized_line.yellow
        else
          colorized_line
        end
      end
      l
    end

    def self.level_from_env
      return ::Logger::DEBUG if ENV["DEBUG"]

      if ENV["LEVEL"]
        ::Logger.const_get(ENV["LEVEL"].upcase)
      else
        ::Logger::INFO
      end
    end
    private_class_method :level_from_env
  end
end
