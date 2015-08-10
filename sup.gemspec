$:.push File.expand_path("../lib", __FILE__)

require 'sup/version'

Gem::Specification.new do |s|
  s.name = "sup"
  s.version = ENV["REL"] || (::Redwood::VERSION == "git" ? "999" : ::Redwood::VERSION)
  s.date = Time.now.strftime "%Y-%m-%d"
  s.authors = ["William Morgan", "Gaute Hope", "Hamish Downer", "Matthieu Rakotojaona"]
  s.email   = "supmua@googlegroups.com"
  s.summary = "A console-based email client with the best features of GMail, mutt and Emacs"
  s.homepage = "http://supmua.org"
  s.license = 'GPL-2'
  s.description = <<-DESC
    Sup is a console-based email client for people with a lot of email.

    * GMail-like thread-centered archiving, tagging and muting
    * Handling mail from multiple mbox and Maildir sources
    * Blazing fast full-text search with a rich query language
    * Multiple accounts - pick the right one when sending mail
    * Ruby-programmable hooks
    * Automatically tracking recent contacts
DESC
  s.post_install_message = <<-EOF
SUP: please note that our old mailing lists have been shut down,
     re-subscribe to supmua@googlegroups.com to discuss and follow
     updates on sup (send email to: supmua+subscribe@googlegroups.com).

     OpenBSD users:
     If your operating system is OpenBSD you have some
     additional, manual steps to do before Sup will work, see:
     https://github.com/sup-heliotrope/sup/wiki/Installation%3A-OpenBSD.
  EOF

  s.files         = `git ls-files -z`.split("\x0")
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]
  s.extra_rdoc_files = Dir.glob("man/*")

  s.required_ruby_version = '>= 2.0.0'

  # this is here to support skipping the xapian-ruby installation on OpenBSD
  # because the xapian-ruby gem doesn't install on OpenBSD, you must install
  # xapian-core and xapian-bindings manually on OpenBSD
  # see https://github.com/sup-heliotrope/sup/wiki/Installation%3A-OpenBSD
  # and https://en.wikibooks.org/wiki/Ruby_Programming/RubyGems#How_to_install_different_versions_of_gems_depending_on_which_version_of_ruby_the_installee_is_using
  s.extensions = %w[ext/mkrf_conf_xapian.rb]

  ## remember to update the xapian dependency in
  ## ext/mkrf_conf_xapian.rb and Gemfile.

  s.add_runtime_dependency "ncursesw", "~> 1.4.0"
  s.add_runtime_dependency "rmail-sup", "~> 1.0.1"
  s.add_runtime_dependency "highline"
  s.add_runtime_dependency "trollop", ">= 1.12"
  s.add_runtime_dependency "lockfile"
  s.add_runtime_dependency "mime-types", "> 2.0"
  s.add_runtime_dependency "locale", "~> 2.0"
  s.add_runtime_dependency "chronic", "~> 0.9.1"
  s.add_runtime_dependency "unicode", "~> 0.4.4"

  s.add_development_dependency "bundler", "~> 1.3"
  s.add_development_dependency "rake"
  s.add_development_dependency 'minitest', '~> 5.5.1'
  s.add_development_dependency "rr", "~> 1.1"
  s.add_development_dependency "gpgme", ">= 2.0.2"
  s.add_development_dependency "pry"

end
