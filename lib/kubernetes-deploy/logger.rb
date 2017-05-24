# frozen_string_literal: true
require 'logger'

module KubernetesDeploy
  module Logger
    def self.build(namespace, context, stream = $stderr, verbose_tags: false)
      l = ::Logger.new(stream)
      l.level = level_from_env

      l.formatter = proc do |severity, datetime, _progname, msg|
        middle = verbose_tags ? "[#{context}][#{namespace}]" : ""
        colorized_line = ColorizedString.new("[#{severity}][#{datetime}]#{middle}\t#{msg}\n")

        case severity
        when "FATAL"
          colorized_line.red
        when "ERROR", "WARN"
          colorized_line.yellow
        when "INFO"
          msg =~ /^\[(KUBESTATUS|Pod)/ ? colorized_line : colorized_line.blue
        else
          colorized_line
        end
      end

      def l.blank_line(level = :info)
        public_send(level, "")
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
