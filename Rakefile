# frozen_string_literal: true
require "bundler/gem_tasks"
require "rake/testtask"

desc("Run integration tests that can be run in parallel")
Rake::TestTask.new(:integration_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/integration/**/*_test.rb']
end

desc("Run integration tests that CANNOT be run in parallel")
Rake::TestTask.new(:serial_integration_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/integration-serial/**/*_test.rb']
end

desc("Run unit tests")
Rake::TestTask.new(:unit_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/unit/**/*_test.rb']
end

desc("Run cli tests")
Rake::TestTask.new(:cli_test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/exe/**/*_test.rb']
end

desc("Run all tests")
task(test: %w(unit_test serial_integration_test integration_test cli_test))

task(default: :test)
