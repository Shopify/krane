# frozen_string_literal: true

module Enumerable
  def with_delayed_exceptions(*catch, &block)
    exceptions = []
    each do |i|
      begin
        block.call(i)
      rescue *catch => e
        exceptions << e
      end
    end.tap { raise exceptions.first if exceptions.first }
  end
end
