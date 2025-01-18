# frozen_string_literal: true

module Krane
  class ExtraLabels
    def self.parse(string)
      extra_labels = {}

      string.split(',').each do |kvp|
        key, value = kvp.split('=', 2)

        if key.blank?
          raise ArgumentError, "key is blank"
        end

        extra_labels[key] = value
      end

      extra_labels
    end
  end
end
