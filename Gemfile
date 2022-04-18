source 'https://rubygems.org/'

if !RbConfig::CONFIG['arch'].include?('openbsd')
  # update version in ext/mkrf_conf_xapian.rb as well.
  if /^2\.0\./ =~ RUBY_VERSION
    gem 'xapian-ruby', ['~> 1.2', '< 1.3.6']
  else
    gem 'xapian-ruby', '~> 1.2'
  end
end

gemspec
