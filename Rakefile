# frozen_string_literal: true

require "rake/testtask"
require "rubocop/rake_task"

# test/all.rb lists every test file explicitly (see test/manifest_test.rb).
Rake::TestTask.new(:test) do |task|
  task.libs << "lib" << "test"
  task.test_files = ["test/all.rb"]
  task.warning = true
end

RuboCop::RakeTask.new

desc "Run the tests and the linter"
task default: [:test, :rubocop]
