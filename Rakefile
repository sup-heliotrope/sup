require 'rubygems'
require 'rake/testtask'
require "bundler/gem_tasks"

Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.test_files = FileList.new('test/**/test_*.rb')
  test.verbose = true
end
task :default => :test

task :travis => [:test, :build]
