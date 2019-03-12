# frozen_string_literal: true

module KubernetesDeploy
  class LabelSelector
    def self.parse(string)
      selector = parse_selector(string)
      unless selector
        raise ArgumentError, "Failed to parse selector."
      end
      new(selector)
    end

    def initialize(hash)
      @selector = hash
    end

    def to_h
      @selector
    end

    def to_s
      return "" if @selector.nil?
      @selector.map { |k, v| "#{k}=#{v}" }.join(",")
    end

    private

    def self.parse_selector(string)
      selector = {}

      string.split(',').each do |kvp|
        key, value = kvp.split('=', 2)

        if key.blank?
          raise ArgumentError, "key is blank"
        end

        if key.end_with?("!")
          raise ArgumentError, "!= selectors are not supported"
        end

        if value&.start_with?("=")
          raise ArgumentError, "== selectors are not supported"
        end

        selector[key] = value
      end

      selector
    end
  end
end
