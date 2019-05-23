# frozen_string_literal: true
require 'logger'
require 'colorized_string'
require 'kubernetes-deploy/deferred_summary_logging'

module KubernetesDeploy
  class FormattedLogger < Logger
    include DeferredSummaryLogging

    def self.indent_four(str)
      "    " + str.to_s.gsub("\n", "\n    ")
    end

    def self.build(namespace = nil, context = nil, stream = $stderr, verbose_prefix: false)
      l = new(stream)
      l.level = level_from_env

      middle = if verbose_prefix
        if namespace.blank?
          raise ArgumentError, 'Must pass a namespace if logging verbosely'
        end
        if context.blank?
          raise ArgumentError, 'Must pass a context if logging verbosely'
        end

        "[#{context}][#{namespace}]"
      end

      l.formatter = proc do |severity, datetime, _progname, msg|
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
