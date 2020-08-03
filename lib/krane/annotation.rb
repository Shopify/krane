# frozen_string_literal: true

module Krane
  module Annotation
    class << self
      def for(suffix)
        "krane.shopify.io/#{suffix}"
      end
    end
  end
end
