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

task :gem do |t|
  sh "gem1.8 build sup.gemspec"
end

task :tarball do |t|
  require "sup-files"
  require "sup-version"
  sh "tar cfvz sup-#{SUP_VERSION}.tgz #{SUP_FILES.join(' ')}"
end
