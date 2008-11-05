require 'rubygems'
require 'hoe'
$:.unshift 'lib' # force loading from ./lib/ if it exists
require 'sup'

## remove hoe dependency entirely
class Hoe
  def extra_dev_deps; @extra_dev_deps.reject { |x| x[0] == "hoe" } end
end

## allow people who use development versions by running "rake gem"
## and installing the resulting gem it to be able to do this. (gem
## versions must be in dotted-digit notation only and can be passed
## with the REL environment variable to "rake gem").
if ENV['REL']
  version = ENV['REL']
else
  version = Redwood::VERSION == "git" ? "999" : Redwood::VERSION
end
Hoe.new('sup', version) do |p|
  p.rubyforge_name = 'sup'
  p.author = "William Morgan"
  p.summary = 'A console-based email client with the best features of GMail, mutt, and emacs. Features full text search, labels, tagged operations, multiple buffers, recent contacts, and more.'
  p.description = p.paragraphs_of('README.txt', 2..9).join("\n\n")
  p.url = p.paragraphs_of('README.txt', 0).first.split(/\n/)[2].gsub(/^\s+/, "")
  p.changes = p.paragraphs_of('History.txt', 0..0).join("\n\n")
  p.email = "wmorgan-sup@masanjin.net"
  p.extra_deps = [['ferret', '>= 0.10.13'], ['ncurses', '>= 0.9.1'], ['rmail', '>= 0.17'], 'highline', 'net-ssh', ['trollop', '>= 1.7'], 'lockfile', 'mime-types', 'gettext', 'fastthread']
end

rule 'ss?.png' => 'ss?-small.png' do |t|
end

## is there really no way to make a rule for this?
WWW_FILES = %w(www/index.html README.txt doc/Philosophy.txt doc/FAQ.txt doc/NewUserGuide.txt www/main.css)

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
