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
  EOF

  s.files         = `git ls-files -z`.split("\x0")
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]
  s.extra_rdoc_files = Dir.glob("man/*")

  s.required_ruby_version = '>= 1.9.3'

  s.add_runtime_dependency "xapian-ruby", "~> 1.2.15"
  s.add_runtime_dependency "ncursesw", "~> 1.4.0"
  s.add_runtime_dependency "rmail-sup", "~> 1.0.1"
  s.add_runtime_dependency "highline"
  s.add_runtime_dependency "trollop", ">= 1.12"
  s.add_runtime_dependency "lockfile"
  s.add_runtime_dependency "mime-types", "~> 1.0"
  s.add_runtime_dependency "locale", "~> 2.0"
  s.add_runtime_dependency "chronic", "~> 0.9.1"
  s.add_runtime_dependency "unicode", "~> 0.4.4"

  s.add_development_dependency "bundler", "~> 1.3"
  s.add_development_dependency "rake"
  s.add_development_dependency "minitest", "~> 4.7"
  s.add_development_dependency "rr", "~> 1.0.5"
  s.add_development_dependency "gpgme", ">= 2.0.2"
end
