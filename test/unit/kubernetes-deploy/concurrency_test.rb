# frozen_string_literal: true
require 'test_helper'

class ConcurrencyTest < KubernetesDeploy::TestCase
  class TestWork
    attr_accessor :worked_by_threads
    def initialize
      @worked_by_threads = []
    end
  end

  def test_split_across_threads_raises_without_a_block
    assert_raises_message(ArgumentError, "Block of work is required") do
      KubernetesDeploy::Concurrency.split_across_threads([TestWork.new])
    end
  end

  def test_split_across_threads_works_with_zero_work
    KubernetesDeploy::Concurrency.split_across_threads([]) do |individual|
      individual.worked_by_threads << Thread.current.object_id
    end
    # nothing raised
  end

  def test_split_across_threads_works_with_one_work
    all_work = [TestWork.new]
    KubernetesDeploy::Concurrency.split_across_threads(all_work) do |individual|
      individual.worked_by_threads << Thread.current.object_id
    end
    assert_work_distribution(all_work, [1])
  end

  def test_split_across_threads_splits_evenly_with_small_work
    all_work = 2.times.with_object([]) { |_, all| all << TestWork.new }
    KubernetesDeploy::Concurrency.split_across_threads(all_work) do |individual|
      individual.worked_by_threads << Thread.current.object_id
    end
    assert_work_distribution(all_work, [1, 1])
  end

  def test_split_across_threads_splits_evenly_with_equal_work_and_threads
    all_work = KubernetesDeploy::Concurrency::MAX_THREADS.times.with_object([]) { |_, all| all << TestWork.new }
    KubernetesDeploy::Concurrency.split_across_threads(all_work) do |individual|
      individual.worked_by_threads << Thread.current.object_id
    end
    assert_work_distribution(all_work, [1, 1, 1, 1, 1, 1, 1, 1])
  end

  def test_split_across_threads_splits_evenly_with_large_work
    all_work = 31.times.with_object([]) { |_, all| all << TestWork.new }
    KubernetesDeploy::Concurrency.split_across_threads(all_work) do |individual|
      individual.worked_by_threads << Thread.current.object_id
    end
    assert_work_distribution(all_work, [4, 4, 4, 4, 4, 4, 4, 3])
  end

  private

  def assert_work_distribution(all_work, expected)
    assert(all_work.all? { |w| w.worked_by_threads.length == 1 }, "Same work done by multiple threads somehow")
    thread_map = all_work.each_with_object(Hash.new { |hash, key| hash[key] = 0 }) do |w, threads|
      threads[w.worked_by_threads.first] += 1
    end
    assert_equal(thread_map.values.sort, expected.sort)
  end
end
