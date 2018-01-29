# frozen_string_literal: true

module KubernetesDeploy
  module Utils
    def self.selector_to_string(selector)
      return "" if selector.nil?
      selector.map { |k, v| "#{k}=#{v}" }.join(",")
    end
  end
end
