require 'rake/testtask'
require "bundler/gem_tasks"

Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.test_files = FileList.new('test/**/test_*.rb')
  test.verbose = true
end
task :default => :test

task :build => [:man]
task :travis => [:test, :build]

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

  Dir.glob("doc/wiki/man/*.md").each do |md|
    m = /^.*\/(?<manpage>[^\/]*)\.md$/.match(md)[:manpage]
    puts "generating manpage for: #{m}.."
    r = system "pandoc -s -f markdown -t man #{md} -o man/#{m}"

    unless r
      puts "failed to generate manpage: #{m}."
      return
    end
  end
end

task :clean do
  ['man', 'pkg'].each do |d|
    puts "cleaning #{d}.."
    FileUtils.rm_r d if Dir.exist? d
  end
end
