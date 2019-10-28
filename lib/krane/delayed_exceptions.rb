# frozen_string_literal: true

module DelayedExceptions
  def with_delayed_exceptions(enumerable, *catch, &block)
    exceptions = []
    enumerable.each do |i|
      begin
        block.call(i)
      rescue *catch => e
        exceptions << e
      end
    end.tap { raise exceptions.first if exceptions.first }
  end
end
