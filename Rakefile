require 'rubygems'
require 'rake/testtask'

Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.test_files = FileList.new('test/test_*.rb').exclude(/test\/test_server.rb/)
  test.verbose = true
end

require 'rubygems/package_task'

load "sup.gemspec"

Gem::PackageTask.new(Redwood::Gemspec) do |pkg|
    pkg.need_tar = true
end

task :travis => [:test, :gem]
