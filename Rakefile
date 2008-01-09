require 'rubygems'
require 'hoe'
$:.unshift 'lib' # force loading from ./lib/ if it exists
require 'sup'

class Hoe
  def extra_deps; @extra_deps.reject { |x| Array(x).first == "hoe" } end
end # thanks to "Mike H"

## allow people who use development versions by running "rake gem"
## and installing the resulting gem it to be able to do this. (gem
## versions must be in dotted-digit notation only).
version = Redwood::VERSION == "git" ? 999 : Redwood::VERSION

Hoe.new('sup', version) do |p|
  p.rubyforge_name = 'sup'
  p.author = "William Morgan"
  p.summary = 'A console-based email client with the best features of GMail, mutt, and emacs. Features full text search, labels, tagged operations, multiple buffers, recent contacts, and more.'
  p.description = p.paragraphs_of('README.txt', 2..9).join("\n\n")
  p.url = p.paragraphs_of('README.txt', 0).first.split(/\n/)[2].gsub(/^\s+/, "")
  p.changes = p.paragraphs_of('History.txt', 0..0).join("\n\n")
  p.email = "wmorgan-sup@masanjin.net"
  p.extra_deps = [['ferret', '>= 0.10.13'], ['ncurses', '>= 0.9.1'], ['rmail', '>= 0.17'], 'highline', 'net-ssh', ['trollop', '>= 1.7'], 'lockfile', 'mime-types']
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
  sh "scp -C #{t.prerequisites * ' '} wmorgan@rubyforge.org:/var/www/gforge-projects/sup/"
end

task :upload_webpage_images => (SCREENSHOTS + SCREENSHOTS_SMALL) do |t|
  sh "scp -C #{t.prerequisites * ' '} wmorgan@rubyforge.org:/var/www/gforge-projects/sup/"
end

# vim: syntax=ruby
# -*- ruby -*-
