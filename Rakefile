require 'rubygems'
require 'rake/testtask'

Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.test_files = FileList.new('test/**/test_*.rb')
  test.verbose = true
end
task :default => :test

require 'rubygems/package_task'
# For those who don't have `rubygems-bundler` installed
load 'sup.gemspec' unless defined? Redwood::Gemspec

Gem::PackageTask.new(Redwood::Gemspec) do |pkg|
  pkg.need_tar = true
end

task :travis => [:test, :gem]
