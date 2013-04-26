## is there really no way to make a rule for this?
WWW_FILES = %w(www/index.html README.txt doc/Philosophy.txt doc/FAQ.txt doc/NewUserGuide.txt www/main.css)

rule 'ss?.png' => 'ss?-small.png' do |t|
end
SCREENSHOTS = FileList["www/ss?.png"]
SCREENSHOTS_SMALL = []
SCREENSHOTS.each do |fn|
  fn =~ /ss(\d+)\.png/
  sfn = "www/ss#{$1}-small.png"
  file sfn => [fn] do |t|
    sh "cat #{fn} | pngtopnm | pnmscale -xysize 320 240 | pnmtopng > #{sfn}"
  end
  SCREENSHOTS_SMALL << sfn
end

task :upload_webpage => WWW_FILES do |t|
  sh "rsync -essh -cavz #{t.prerequisites * ' '} wmorgan@rubyforge.org:/var/www/gforge-projects/sup/"
end

task :upload_webpage_images => (SCREENSHOTS + SCREENSHOTS_SMALL) do |t|
  sh "rsync -essh -cavz #{t.prerequisites * ' '} wmorgan@rubyforge.org:/var/www/gforge-projects/sup/"
end

# vim: syntax=ruby
# -*- ruby -*-
task :upload_report do |t|
  sh "ditz html ditz"
  sh "rsync -essh -cavz ditz wmorgan@rubyforge.org:/var/www/gforge-projects/sup/"
end

require 'rubygems'
require 'rake/testtask'

Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.test_files = FileList.new('test/test_*.rb').exclude(/test\/test_server.rb/)
  test.verbose = true
end

$:.push "lib"
require 'rubygems/package_task'

unless Kernel.respond_to?(:require_relative)
  require "./sup-files"
  require "./sup-version"
else
  require_relative "sup-files"
  require_relative "sup-version"
end

spec = Gem::Specification.new do |s|
  s.name = %q{sup}
  s.version = SUP_VERSION
  s.date = Time.now.strftime "%Y-%m-%d"
  s.authors = ["William Morgan"]
  s.email   = "sup-talk@rubyforge.org"
  s.summary = %q{A console-based email client with the best features of GMail, mutt, and emacs. Features full text search, labels, tagged operations, multiple buffers, recent contacts, and more.}
  s.homepage = %q{https://github.com/sup-heliotrope/sup/wiki}
  s.description = %q{Sup is a console-based email client for people with a lot of email. It supports tagging, very fast full-text search, automatic contact-list management, and more. If you're the type of person who treats email as an extension of your long-term memory, Sup is for you.  Sup makes it easy to: - Handle massive amounts of email.  - Mix email from different sources: mbox files (even across different machines), Maildir directories, POP accounts, and GMail accounts.  - Instantaneously search over your entire email collection. Search over body text, or use a query language to combine search predicates in any way.  - Handle multiple accounts. Replying to email sent to a particular account will use the correct SMTP server, signature, and from address.  - Add custom code to handle certain types of messages or to handle certain types of text within messages.  - Organize email with user-defined labels, automatically track recent contacts, and much more!  The goal of Sup is to become the email client of choice for nerds everywhere.}
  s.files = SUP_FILES
  s.executables = SUP_EXECUTABLES

  s.add_dependency "xapian-full-alaveteli", "~> 1.2"
  s.add_dependency "ncursesw"
  s.add_dependency "rmail", ">= 0.17"
  s.add_dependency "highline"
  s.add_dependency "trollop", ">= 1.12"
  s.add_dependency "lockfile"
  s.add_dependency "mime-types", "~> 1"
  s.add_dependency "gettext"
end

Gem::PackageTask.new(spec) do |pkg|
    pkg.need_tar = true
end

task :tarball => ["pkg/sup-#{SUP_VERSION}.tgz"]
task :travis => [:test, :gem]
