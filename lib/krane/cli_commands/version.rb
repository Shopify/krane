# frozen_string_literal: true

require 'krane/version'

module Krane
  module CLICommands
    class Version
      OPTIONS = {
        "output" => { aliases: "-o", enum: ["json", "yaml"] },
      }

      def self.from_options(options)
        version = Krane::Version.new
        output = case options[:output]
        when "json"
          JSON.pretty_generate(version.to_h)
        when "yaml"
          version.to_h.to_yaml
        else
          "Krane version: #{version}"
        end
        $stdout.puts output
      end
    end
  end
end
