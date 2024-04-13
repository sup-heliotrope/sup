require 'rubygems'
require 'rubygems/command.rb'
require 'rubygems/dependency_installer.rb'
require 'rbconfig'

begin
  Gem::Command.build_args = ARGV
rescue NoMethodError
end

puts "xapian: platform specific dependencies.."

destination = File.writable?(Gem.dir) ? Gem.dir : Gem.user_dir
inst = Gem::DependencyInstaller.new(:install_dir => destination)
begin

  if not ENV.include? "SUP_SKIP_XAPIAN_GEM_INSTALL"
    # update version in Gemfile as well
    name    = "xapian-ruby"
    version =
      if /^2\.0\./ =~ RUBY_VERSION
        ["~> 1.2", "< 1.3.6"]
      else
        "~> 1.2"
      end

    begin
      # try to load gem

      gem name, version
      STDERR.puts "xapian: already installed."

    rescue Gem::LoadError

      STDERR.puts "xapian: installing xapian-ruby.."
      inst.install name, version

    end
  else
    STDERR.puts "xapian: you have to install xapian-core and xapian-bindings manually"
  end

rescue StandardError => e
  STDERR.puts "Unable to install #{name} gem: #{e.inspect}"
  exit(1)

end

# create dummy rakefile to indicate success
f = File.open(File.join(File.dirname(__FILE__), "Rakefile"), "w")
f.write("task :default\n")
f.close

