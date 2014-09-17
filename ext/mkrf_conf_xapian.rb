require 'rubygems'
require 'rubygems/command.rb'
require 'rubygems/dependency_installer.rb'
require 'rbconfig'

begin
  Gem::Command.build_args = ARGV
rescue NoMethodError
end

puts "xapian: platform specific dependencies.."

inst = Gem::DependencyInstaller.new
begin

  if !RbConfig::CONFIG['arch'].include?('openbsd')
    name    = "xapian-ruby"
    version = "~> 1.2.15"

    begin
      # try to load gem

      STDERR.puts "xapian: already installed."
      gem name, version

    rescue Gem::LoadError

      STDERR.puts "xapian: installing xapian-ruby.."
      inst.install name, version

    end
  else
    STDERR.puts "xapian: openbsd: you have to install xapian-core and xapian-bindings manually, have a look at: https://github.com/sup-heliotrope/sup/wiki/Installation%3A-OpenBSD"
  end

rescue

  exit(1)

end

# create dummy rakefile to indicate success
f = File.open(File.join(File.dirname(__FILE__), "Rakefile"), "w")
f.write("task :default\n")
f.close

