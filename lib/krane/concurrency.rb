# frozen_string_literal: true
module Krane
  module Concurrency
    MAX_THREADS = 8

    def self.split_across_threads(all_work, max_threads: MAX_THREADS, &block)
      return if all_work.empty?
      raise ArgumentError, "Block of work is required" unless block_given?

      slice_size = ((all_work.length + max_threads - 1) / max_threads)
      threads = []
      all_work.each_slice(slice_size) do |work_group|
        threads << Thread.new { work_group.each(&block) }
      end
      threads.each(&:join)
    end
  end
end
