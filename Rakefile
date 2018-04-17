# frozen_string_literal: true
require "bundler/gem_tasks"
require "rake/testtask"

files = {
  integration_test: FileList['test/integration/**/*_test.rb'],
  serial_integration_test: FileList['test/integration-serial/**/*_test.rb'],
  unit_test: FileList['test/unit/**/*_test.rb']
}

desc "Run integration tests that can be run in parallel"
Rake::TestTask.new(:integration_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = files[t.name]
end

desc "Run integration tests that CANNOT be run in parallel"
Rake::TestTask.new(:serial_integration_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = files[t.name]
end

desc "Run unit tests"
Rake::TestTask.new(:unit_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = files[t.name]
end

all_test = %w(unit_test serial_integration_test integration_test)

tests_to_run = if ENV['TEST']
  files.select { |_, v| v.include?(ENV['TEST']) }.keys
else
  all_test
end

desc "Run all tests"
task test: tests_to_run

task default: :test
