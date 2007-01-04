require 'rubygems'
require 'yaml'
require 'zlib'
require 'thread'
require 'fileutils'

class Object
  ## this is for debugging purposes because i keep calling #id on the
  ## wrong object and i want it to throw an exception
  def id
    raise "wrong id called on #{self.inspect}"
  end
end

module Redwood
  VERSION = "0.0.4"

  BASE_DIR   = ENV["SUP_BASE"] || File.join(ENV["HOME"], ".sup")
  CONFIG_FN  = File.join(BASE_DIR, "config.yaml")
  SOURCE_FN  = File.join(BASE_DIR, "sources.yaml")
  LABEL_FN   = File.join(BASE_DIR, "labels.txt")
  PERSON_FN   = File.join(BASE_DIR, "people.txt")
  CONTACT_FN = File.join(BASE_DIR, "contacts.txt")
  DRAFT_DIR  = File.join(BASE_DIR, "drafts")
  SENT_FN    = File.join(BASE_DIR, "sent.mbox")

  YAML_DOMAIN = "masanjin.net"
  YAML_DATE = "2006-10-01"

## record exceptions thrown in threads nicely
  $exception = nil
  def reporting_thread
    ::Thread.new do
      begin
        yield
      rescue Exception => e
        $exception ||= e
        raise
      end
    end
  end
  module_function :reporting_thread

## one-stop shop for yamliciousness
  def register_yaml klass, props
    vars = props.map { |p| "@#{p}" }
    path = klass.name.gsub(/::/, "/")
    
    klass.instance_eval do
      define_method(:to_yaml_properties) { vars }
      define_method(:to_yaml_type) { "!#{YAML_DOMAIN},#{YAML_DATE}/#{path}" }
    end

    YAML.add_domain_type("#{YAML_DOMAIN},#{YAML_DATE}", path) do |type, val|
      klass.new(*props.map { |p| val[p] })
    end
  end

  def save_yaml_obj object, fn, compress=false
    if compress
      Zlib::GzipWriter.open(fn) { |f| f.puts object.to_yaml }
    else
      File.open(fn, "w") { |f| f.puts object.to_yaml }
    end
  end

  def load_yaml_obj fn, compress=false
    if File.exists? fn
      if compress
        Zlib::GzipReader.open(fn) { |f| YAML::load f }
      else
        YAML::load_file fn
      end
    end
  end

  def start
    Redwood::PersonManager.new Redwood::PERSON_FN
    Redwood::SentManager.new Redwood::SENT_FN
    Redwood::ContactManager.new Redwood::CONTACT_FN
    Redwood::LabelManager.new Redwood::LABEL_FN
    Redwood::AccountManager.new $config[:accounts]
    Redwood::DraftManager.new Redwood::DRAFT_DIR
    Redwood::UpdateManager.new
    Redwood::PollManager.new
  end

  def finish
    Redwood::LabelManager.save
    Redwood::ContactManager.save
    Redwood::PersonManager.save
  end

  module_function :register_yaml, :save_yaml_obj, :load_yaml_obj, :start, :finish
end

## set up default configuration file
if File.exists? Redwood::CONFIG_FN
  $config = Redwood::load_yaml_obj Redwood::CONFIG_FN
else
  $config = {
    :accounts => {
      :default => {
        :name => "Your Name Here",
        :email => "your.email.here@domain.tld",
        :alternates => [],
        :sendmail => "/usr/sbin/sendmail -oem -ti",
        :signature => File.join(ENV["HOME"], ".signature")
      }
    },
    :editor => ENV["EDITOR"] || "/usr/bin/vi",
  }
  begin
    FileUtils.mkdir_p Redwood::BASE_DIR
    Redwood::save_yaml_obj $config, Redwood::CONFIG_FN
  rescue StandardError => e
    $stderr.puts "warning: #{e.message}"
  end
end

require "sup/util"
require "sup/update"
require "sup/message"
require "sup/source"
require "sup/mbox"
require "sup/imap"
require "sup/person"
require "sup/account"
require "sup/thread"
require "sup/index"
require "sup/textfield"
require "sup/buffer"
require "sup/keymap"
require "sup/mode"
require "sup/colormap"
require "sup/label"
require "sup/contact"
require "sup/tagger"
require "sup/draft"
require "sup/poll"
require "sup/modes/scroll-mode"
require "sup/modes/text-mode"
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
require "sup/modes/log-mode"
require "sup/modes/poll-mode"
require "sup/logger"
require "sup/sent"

module Redwood
  def log s; Logger.log s; end
  module_function :log
end

$:.each do |base|
  d = File.join base, "sup/share/modes/"
  Redwood::Mode.load_all_modes d if File.directory? d
end
