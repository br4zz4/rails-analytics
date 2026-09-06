# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = Rake::FileList["test/**/*_test.rb"].exclude("test/dummy/**/*_test.rb")
  t.warning = false
end

Rake::TestTask.new(:integration) do |t|
  t.libs << "test/dummy/test"
  t.pattern = "test/dummy/test/**/*_test.rb"
  t.warning = false
end

task default: [:test, :integration]
