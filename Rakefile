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

task :gem => [:man]

Gem::PackageTask.new(Redwood::Gemspec) do |pkg|
  pkg.need_tar = true
end

task :travis => [:test, :gem]

def test_pandoc
  return system("pandoc -v > /dev/null 2>&1")
end

task :man do
  puts "building manpages from wiki.."
  unless test_pandoc
    puts "no pandoc installed, needed for manpage generation."
    return
  end

  # test if wiki is cloned
  unless Dir.exist? 'doc/wiki/man'
    puts "wiki git repository is not cloned in doc/wiki, try: git submodule update --init."
    return
  end

  unless Dir.exist? 'man'
    Dir.mkdir 'man'
  end

  Dir.glob("doc/wiki/man/*.1").split.each do |m|
    puts "generating manpage for: #{m}.."
    md = "doc/wiki/#{m}.md"
    system "pandoc -s -f markdown -t man #{md} -o #{m}"
  end
end

task :clean do
  ['man', 'pkg'].each do |d|
    puts "cleaning #{d}.."
    FileUtils.rm_r d if Dir.exist? d
  end
end
