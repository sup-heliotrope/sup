require 'rubygems'
require 'yaml'
require 'zlib'
require 'thread'
require 'fileutils'
require 'gettext'
require 'curses'
begin
  require 'fastthread'
rescue LoadError
end

class Object
  ## this is for debugging purposes because i keep calling #id on the
  ## wrong object and i want it to throw an exception
  def id
    raise "wrong id called on #{self.inspect}"
  end
end

class Module
  def yaml_properties *props
    props = props.map { |p| p.to_s }
    vars = props.map { |p| "@#{p}" }
    klass = self
    path = klass.name.gsub(/::/, "/")

    klass.instance_eval do
      define_method(:to_yaml_properties) { vars }
      define_method(:to_yaml_type) { "!#{Redwood::YAML_DOMAIN},#{Redwood::YAML_DATE}/#{path}" }
    end

    YAML.add_domain_type("#{Redwood::YAML_DOMAIN},#{Redwood::YAML_DATE}", path) do |type, val|
      klass.new(*props.map { |p| val[p] })
    end
  end
end

module Redwood
  VERSION = "git"

  BASE_DIR   = ENV["SUP_BASE"] || File.join(ENV["HOME"], ".sup")
  CONFIG_FN  = File.join(BASE_DIR, "config.yaml")
  COLOR_FN   = File.join(BASE_DIR, "colors.yaml")
  SOURCE_FN  = File.join(BASE_DIR, "sources.yaml")
  LABEL_FN   = File.join(BASE_DIR, "labels.txt")
  CONTACT_FN = File.join(BASE_DIR, "contacts.txt")
  DRAFT_DIR  = File.join(BASE_DIR, "drafts")
  SENT_FN    = File.join(BASE_DIR, "sent.mbox")
  LOCK_FN    = File.join(BASE_DIR, "lock")
  SUICIDE_FN = File.join(BASE_DIR, "please-kill-yourself")
  HOOK_DIR   = File.join(BASE_DIR, "hooks")
  SEARCH_FN  = File.join(BASE_DIR, "searches.txt")

  YAML_DOMAIN = "masanjin.net"
  YAML_DATE = "2006-10-01"

  DEFAULT_NEW_INDEX_TYPE = 'xapian'

  ## record exceptions thrown in threads nicely
  @exceptions = []
  @exception_mutex = Mutex.new

  attr_reader :exceptions
  def record_exception e, name
    @exception_mutex.synchronize do
      @exceptions ||= []
      @exceptions << [e, name]
    end
  end

  def reporting_thread name
    if $opts[:no_threads]
      yield
    else
      ::Thread.new do
        begin
          yield
        rescue Exception => e
          record_exception e, name
        end
      end
    end
  end

  module_function :reporting_thread, :record_exception, :exceptions

## one-stop shop for yamliciousness
  def save_yaml_obj o, fn, safe=false
    o = if o.is_a?(Array)
      o.map { |x| (x.respond_to?(:before_marshal) && x.before_marshal) || x }
    elsif o.respond_to? :before_marshal
      o.before_marshal
    else
      o
    end

    if safe
      safe_fn = "#{File.dirname fn}/safe_#{File.basename fn}"
      mode = File.stat(fn).mode if File.exists? fn
      File.open(safe_fn, "w", mode) { |f| f.puts o.to_yaml }
      FileUtils.mv safe_fn, fn
    else
      File.open(fn, "w") { |f| f.puts o.to_yaml }
    end
  end

  def load_yaml_obj fn, compress=false
    o = if File.exists? fn
      if compress
        Zlib::GzipReader.open(fn) { |f| YAML::load f }
      else
        YAML::load_file fn
      end
    end
    if o.is_a?(Array)
      o.each { |x| x.after_unmarshal! if x.respond_to?(:after_unmarshal!) }
    else
      o.after_unmarshal! if o.respond_to?(:after_unmarshal!)
    end
    o
  end

  def start
    Redwood::SentManager.init $config[:sent_source] || 'sup://sent'
    Redwood::ContactManager.init Redwood::CONTACT_FN
    Redwood::LabelManager.init Redwood::LABEL_FN
    Redwood::AccountManager.init $config[:accounts]
    Redwood::DraftManager.init Redwood::DRAFT_DIR
    Redwood::UpdateManager.init
    Redwood::PollManager.init
    Redwood::CryptoManager.init
    Redwood::UndoManager.init
    Redwood::SourceManager.init
    Redwood::SearchManager.init Redwood::SEARCH_FN
  end

  def finish
    Redwood::LabelManager.save if Redwood::LabelManager.instantiated?
    Redwood::ContactManager.save if Redwood::ContactManager.instantiated?
    Redwood::BufferManager.deinstantiate! if Redwood::BufferManager.instantiated?
    Redwood::SearchManager.save if Redwood::SearchManager.instantiated?
  end

  ## not really a good place for this, so I'll just dump it here.
  ##
  ## a source error is either a FatalSourceError or an OutOfSyncSourceError.
  ## the superclass SourceError is just a generic.
  def report_broken_sources opts={}
    return unless BufferManager.instantiated?

    broken_sources = SourceManager.sources.select { |s| s.error.is_a? FatalSourceError }
    unless broken_sources.empty?
      BufferManager.spawn_unless_exists("Broken source notification for #{broken_sources.join(',')}", opts) do
        TextMode.new(<<EOM)
Source error notification
-------------------------

Hi there. It looks like one or more message sources is reporting
errors. Until this is corrected, messages from these sources cannot
be viewed, and new messages will not be detected.

#{broken_sources.map { |s| "Source: " + s.to_s + "\n Error: " + s.error.message.wrap(70).join("\n        ")}.join("\n\n")}
EOM
#' stupid ruby-mode
      end
    end

    desynced_sources = SourceManager.sources.select { |s| s.error.is_a? OutOfSyncSourceError }
    unless desynced_sources.empty?
      BufferManager.spawn_unless_exists("Out-of-sync source notification for #{broken_sources.join(',')}", opts) do
        TextMode.new(<<EOM)
Out-of-sync source notification
-------------------------------

Hi there. It looks like one or more sources has fallen out of sync
with my index. This can happen when you modify these sources with
other email clients. (Sorry, I don't play well with others.)

Until this is corrected, messages from these sources cannot be viewed,
and new messages will not be detected. Luckily, this is easy to correct!

#{desynced_sources.map do |s|
  "Source: " + s.to_s + 
   "\n Error: " + s.error.message.wrap(70).join("\n        ") + 
   "\n   Fix: sup-sync --changed #{s.to_s}"
  end}
EOM
#' stupid ruby-mode
      end
    end
  end

  ## to be called by entry points in bin/, to ensure that
  ## their versions match up against the library versions.
  ##
  ## this is a perennial source of bug reports from people
  ## who both use git and have a gem version installed.
  def check_library_version_against v
    unless Redwood::VERSION == v
      $stderr.puts <<EOS
Error: version mismatch!
The sup executable is at version #{v.inspect}.
The sup libraries are at version #{Redwood::VERSION.inspect}.

Your development environment may be picking up code from a
rubygems installation of sup.

If you're running from git with a commandline like

  ruby -Ilib #{$0}

try this instead:

  RUBY_INVOCATION="ruby -Ilib" ruby -Ilib #{$0}

You can also try `gem uninstall sup` and removing all Sup rubygems.

EOS
      abort
    end
  end

  module_function :save_yaml_obj, :load_yaml_obj, :start, :finish,
                  :report_broken_sources, :check_library_version_against
end

## set up default configuration file
if File.exists? Redwood::CONFIG_FN
  $config = Redwood::load_yaml_obj Redwood::CONFIG_FN
  abort "#{Redwood::CONFIG_FN} is not a valid configuration file (it's a #{$config.class}, not a hash)" unless $config.is_a?(Hash)
else
  require 'etc'
  require 'socket'
  name = Etc.getpwnam(ENV["USER"]).gecos.split(/,/).first rescue nil
  name ||= ENV["USER"]
  email = ENV["USER"] + "@" + 
    begin
      Socket.gethostbyname(Socket.gethostname).first
    rescue SocketError
      Socket.gethostname
    end

  $config = {
    :accounts => {
      :default => {
        :name => name,
        :email => email,
        :alternates => [],
        :sendmail => "/usr/sbin/sendmail -oem -ti",
        :signature => File.join(ENV["HOME"], ".signature")
      }
    },
    :editor => ENV["EDITOR"] || "/usr/bin/vim -f -c 'setlocal spell spelllang=en_us' -c 'set filetype=mail'",
    :thread_by_subject => false,
    :edit_signature => false,
    :ask_for_to => true,
    :ask_for_cc => true,
    :ask_for_bcc => false,
    :ask_for_subject => true,
    :confirm_no_attachments => true,
    :confirm_top_posting => true,
    :jump_to_open_message => true,
    :discard_snippets_from_encrypted_messages => false,
    :default_attachment_save_dir => "",
    :sent_source => "sup://sent",
    :poll_interval => 300
  }
  begin
    FileUtils.mkdir_p Redwood::BASE_DIR
    Redwood::save_yaml_obj $config, Redwood::CONFIG_FN
  rescue StandardError => e
    $stderr.puts "warning: #{e.message}"
  end
end

require "sup/util"
require "sup/hook"

## we have to initialize this guy first, because other classes must
## reference it in order to register hooks, and they do that at parse
## time.
Redwood::HookManager.init Redwood::HOOK_DIR

## everything we need to get logging working
require "sup/logger"
Redwood::Logger.init.add_sink $stderr
include Redwood::LogsStuff

## determine encoding and character set
  $encoding = Locale.current.charset
  if $encoding
    debug "using character set encoding #{$encoding.inspect}"
  else
    warn "can't find character set by using locale, defaulting to utf-8"
    $encoding = "UTF-8"
  end

require "sup/buffer"
require "sup/keymap"
require "sup/mode"
require "sup/modes/scroll-mode"
require "sup/modes/text-mode"
require "sup/modes/log-mode"
require "sup/update"
require "sup/message-chunks"
require "sup/message"
require "sup/source"
require "sup/mbox"
require "sup/maildir"
require "sup/imap"
require "sup/person"
require "sup/account"
require "sup/thread"
require "sup/interactive-lock"
require "sup/index"
require "sup/textfield"
require "sup/colormap"
require "sup/label"
require "sup/contact"
require "sup/tagger"
require "sup/draft"
require "sup/poll"
require "sup/crypto"
require "sup/undo"
require "sup/horizontal-selector"
require "sup/modes/line-cursor-mode"
require "sup/modes/help-mode"
require "sup/modes/edit-message-mode"
require "sup/modes/compose-mode"
require "sup/modes/resume-mode"
require "sup/modes/forward-mode"
require "sup/modes/reply-mode"
require "sup/modes/label-list-mode"
require "sup/modes/contact-list-mode"
require "sup/modes/thread-view-mode"
require "sup/modes/thread-index-mode"
require "sup/modes/label-search-results-mode"
require "sup/modes/search-results-mode"
require "sup/modes/person-search-results-mode"
require "sup/modes/inbox-mode"
require "sup/modes/buffer-list-mode"
require "sup/modes/poll-mode"
require "sup/modes/file-browser-mode"
require "sup/modes/completion-mode"
require "sup/modes/console-mode"
require "sup/sent"
require "sup/search"
require "sup/modes/search-list-mode"

$:.each do |base|
  d = File.join base, "sup/share/modes/"
  Redwood::Mode.load_all_modes d if File.directory? d
end
