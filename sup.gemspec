lib = File.expand_path("../lib", __FILE__)
$:.unshift(lib) unless $:.include?(lib)

require 'sup/version'

# Files
SUP_EXECUTABLES = %w(sup sup-add sup-config sup-dump sup-import-dump
  sup-recover-sources sup-sync sup-sync-back sup-tweak-labels
  sup-psych-ify-config-files)
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
    # TODO: might want to add index migrating script here, too
    s.post_install_message = <<-EOF
SUP: Please run `sup-psych-ify-config-files` to migrate from 0.13 to 0.14
    EOF
    s.files = SUP_FILES
    s.executables = SUP_EXECUTABLES

    s.required_ruby_version = '>= 1.9.2'

    s.add_runtime_dependency "xapian-ruby", "~> 1.2.15"
    s.add_runtime_dependency "ncursesw-sup", "~> 1.3.1"
    s.add_runtime_dependency "rmail", ">= 0.17"
    s.add_runtime_dependency "highline"
    s.add_runtime_dependency "trollop", ">= 1.12"
    s.add_runtime_dependency "lockfile"
    s.add_runtime_dependency "mime-types", "~> 1.0"
    s.add_runtime_dependency "locale", "~> 2.0"
    s.add_runtime_dependency "chronic", "~> 0.9.1"

    s.add_development_dependency "bundler", "~> 1.3"
    s.add_development_dependency "rake"
    s.add_development_dependency "minitest", "~> 4.7"
    s.add_development_dependency "rr", "~> 1.0.5"
  end
end
