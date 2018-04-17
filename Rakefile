# frozen_string_literal: true
require "bundler/gem_tasks"
require "rake/testtask"

test_to_files = {
  integration_test: FileList['test/integration/**/*_test.rb'],
  serial_integration_test: FileList['test/integration-serial/**/*_test.rb'],
  unit_test: FileList['test/unit/**/*_test.rb']
}

desc "Run integration tests that can be run in parallel"
Rake::TestTask.new(:integration_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = test_to_files[t.name]
end

desc "Run integration tests that CANNOT be run in parallel"
Rake::TestTask.new(:serial_integration_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = test_to_files[t.name]
end

desc "Run unit tests"
Rake::TestTask.new(:unit_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = test_to_files[t.name]
end

tests_to_run = if ENV['TEST']
  test_to_files.select { |_, v| v.include?(ENV['TEST']) }.keys
else
  test_to_files.keys
end

desc "Run all tests"
task test: tests_to_run

task default: :test
