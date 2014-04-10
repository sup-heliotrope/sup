require 'rubygems'
require 'rake/testtask'
require "bundler/gem_tasks"

Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.test_files = FileList.new('test/**/test_*.rb')
  test.verbose = true
end
task :default => :test

require 'rubygems/package_task'
# For those who don't have `rubygems-bundler` installed
load 'sup.gemspec' unless defined? Redwood::Gemspec

task :gem => [:doc]

Gem::PackageTask.new(Redwood::Gemspec) do |pkg|
  pkg.need_tar = true
end

task :travis => [:test, :gem]

def test_pandoc
  return system("pandoc -v > /dev/null 2>&1")
end

task :doc do
  puts "building manpages from wiki.."
  unless test_pandoc
    puts "no pandoc installed, needed for manpage generation."
    return
  end

  # test if wiki is cloned
  unless File.exist? 'doc/wiki/man/manpage.md'
    puts "wiki git repository is not cloned in doc/wiki."
    return
  end

  unless Dir.exist? 'man'
    Dir.mkdir 'man'
  end

  manpages = FileList.new('doc/wiki/man/*.md')
  manpages.each do |m|
    puts "generating manpage for: #{m}.."
    system "pandoc -s -f markdown -t man #{m} -o man/#{File.basename(m).gsub(".md","")}.1"
  end
end

task :clean do
  FileUtils.rm_r 'man'
  FileUtils.rm_r 'pkg'
end
