lib = File.expand_path("../lib", __FILE__)
$:.unshift(lib) unless $:.include?(lib)

require 'sup/version'

# Files
SUP_EXECUTABLES = %w(sup sup-add sup-config sup-dump sup-import-dump
  sup-recover-sources sup-sync sup-sync-back sup-tweak-labels)
SUP_EXTRA_FILES = %w(CONTRIBUTORS README.md LICENSE History.txt ReleaseNotes)
SUP_FILES =
  SUP_EXTRA_FILES +
  SUP_EXECUTABLES.map { |f| "bin/#{f}" } +
  Dir["lib/**/*.rb"]


module Redwood
  Gemspec = Gem::Specification.new do |s|
    s.name = "sup"
    s.version = ENV["REL"] || (::Redwood::VERSION == "git" ? "999" : ::Redwood::VERSION)
    s.date = Time.now.strftime "%Y-%m-%d"
    s.authors = ["William Morgan", "Gaute Hope", "Hamish Downer", "Matthieu Rakotojaona"]
    s.email   = "sup-talk@rubyforge.org"
    s.summary = "A console-based email client with the best features of GMail, mutt and Emacs"
    s.homepage = "http://supmua.org"
    s.description = <<-DESC
      Sup is a console-based email client for people with a lot of email.

      * GMail-like thread-centered archiving, tagging and muting
      * Handling mail from multiple mbox and Maildir sources
      * Blazing fast full-text search with a rich query language
      * Multiple accounts - pick the right one when sending mail
      * Ruby-programmable hooks
      * Automatically tracking recent contacts
DESC
    s.license = 'GPL-2'
    s.files = SUP_FILES
    s.executables = SUP_EXECUTABLES

    s.add_dependency "xapian-full-alaveteli", "~> 1.2"
    s.add_dependency "ncursesw-sup", "~> 1.3", ">= 1.3.1"
    s.add_dependency "rmail", ">= 0.17"
    s.add_dependency "highline"
    s.add_dependency "trollop", ">= 1.12"
    s.add_dependency "lockfile"
    s.add_dependency "mime-types", "~> 1"
    s.add_dependency "locale", "~> 2.0"
    s.add_dependency "chronic", "~> 0.9", ">= 0.9.1"

    s.add_development_dependency "bundler", "~> 1.3"
    s.add_development_dependency "rake"
    s.add_development_dependency "minitest", "~> 4"
    s.add_development_dependency "rr", "~> 1.0"
  end
end
