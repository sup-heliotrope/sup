require 'rake/testtask'
require "bundler/gem_tasks"

# Manifest.txt file in same folder as this Rakefile
manifest_filename = "#{File.dirname(__FILE__)}/Manifest.txt"
git_ls_files_command = "git ls-files | LC_ALL=C sort"

Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.test_files = FileList.new('test/**/test_*.rb')
  test.verbose = true
end
task :default => :test

task :build => [:man]
task :travis => [:test, :check_manifest, :build]

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

task :manifest do
  manifest = `#{git_ls_files_command}`
  if $?.success? then
    puts "Writing `git ls-files` output to #{manifest_filename}"
    File.write(manifest_filename, manifest, mode: 'w')
  else
    abort "Failed to generate Manifest.txt (with `git ls-files`)"
  end
end

task :check_manifest do
  manifest = `#{git_ls_files_command}`
  manifest_file_contents = File.read(manifest_filename)
  if manifest == manifest_file_contents
    puts "Manifest.txt OK"
  else
    puts "Manifest from `git ls-files`:\n#{manifest}"
    STDERR.puts "Manifest.txt outdated. Please commit an updated Manifest.txt"
    STDERR.puts "To generate Manifest.txt, run: rake manifest"
    abort "Manifest.txt does not match `git ls-files`"
  end
end
