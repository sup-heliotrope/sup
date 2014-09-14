require 'rubygems'
require 'rubygems/command.rb'
require 'rubygems/dependency_installer.rb'
require 'rbconfig'

begin
  Gem::Command.build_args = ARGV
rescue NoMethodError
end

inst = Gem::DependencyInstaller.new
begin
  if RbConfig::CONFIG['arch'].include?('openbsd')
    # TODO: in theory, we could put the OpenBSD install steps here
    # see https://github.com/sup-heliotrope/sup/wiki/Installation%3A-OpenBSD
  else
    inst.install "xapian-ruby", "~> 1.2.15"
 end
rescue
  exit(1)
end
f = File.open(File.join(File.dirname(__FILE__), "Rakefile"), "w") # create dummy rakefile to indicate success
f.write("task :default\n")
f.close
