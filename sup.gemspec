$:.push "lib"

require "sup-files"
require "sup-version"

Gem::Specification.new do |s|
  s.name = %q{sup}
  s.version = SUP_VERSION
  s.date = Time.now.to_s
  s.authors = ["William Morgan"]
  s.email = %q{wmorgan-sup@masanjin.net}
  s.summary = %q{A console-based email client with the best features of GMail, mutt, and emacs. Features full text search, labels, tagged operations, multiple buffers, recent contacts, and more.}
  s.homepage = %q{http://sup.rubyforge.org/}
  s.description = %q{Sup is a console-based email client for people with a lot of email. It supports tagging, very fast full-text search, automatic contact-list management, and more. If you're the type of person who treats email as an extension of your long-term memory, Sup is for you.  Sup makes it easy to: - Handle massive amounts of email.  - Mix email from different sources: mbox files (even across different machines), Maildir directories, IMAP folders, POP accounts, and GMail accounts.  - Instantaneously search over your entire email collection. Search over body text, or use a query language to combine search predicates in any way.  - Handle multiple accounts. Replying to email sent to a particular account will use the correct SMTP server, signature, and from address.  - Add custom code to handle certain types of messages or to handle certain types of text within messages.  - Organize email with user-defined labels, automatically track recent contacts, and much more!  The goal of Sup is to become the email client of choice for nerds everywhere.}
  s.files = SUP_FILES
  s.executables = SUP_EXECUTABLES

  s.add_dependency "ferret", ">= 0.11.6"
  s.add_dependency "ncurses", ">= 0.9.1"
  s.add_dependency "rmail", ">= 0.17"
  s.add_dependency "highline"
  s.add_dependency "net-ssh"
  s.add_dependency "trollop", ">= 1.12"
  s.add_dependency "lockfile"
  s.add_dependency "mime-types", "~> 1"
  s.add_dependency "gettext"
  s.add_dependency "fastthread"

  puts s.files
end 
