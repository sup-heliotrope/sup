require "sup/rfc2047"
require "monitor"

module Redwood

class SourceError < StandardError
  def initialize *a
    raise "don't instantiate me!" if SourceError.is_a?(self.class)
    super
  end
end
class OutOfSyncSourceError < SourceError; end
class FatalSourceError < SourceError; end

class Source
  ## Implementing a new source should be easy, because Sup only needs
  ## to be able to:
  ##  1. See how many messages it contains
  ##  2. Get an arbitrary message
  ##  3. (optional) see whether the source has marked it read or not
  ##
  ## In particular, Sup doesn't need to move messages, mark them as
  ## read, delete them, or anything else. (Well, it's nice to be able
  ## to delete them, but that is optional.)
  ##
  ## Messages are identified internally based on the message id, and stored
  ## with an unique document id. Along with the message, source information
  ## that can contain arbitrary fields (set up by the source) is stored. This
  ## information will be passed back to the source when a message in the
  ## index (Sup database) needs to be identified to its source, e.g. when
  ## re-reading or modifying a unique message.
  ##
  ## To write a new source, subclass this class, and implement:
  ##
  ## - initialize
  ## - load_header offset
  ## - load_message offset
  ## - raw_header offset
  ## - raw_message offset
  ## - store_message (optional)
  ## - poll (loads new messages)
  ## - go_idle (optional)
  ##
  ## All exceptions relating to accessing the source must be caught
  ## and rethrown as FatalSourceErrors or OutOfSyncSourceErrors.
  ## OutOfSyncSourceErrors should be used for problems that a call to
  ## sup-sync will fix (namely someone's been playing with the source
  ## from another client); FatalSourceErrors can be used for anything
  ## else (e.g. the imap server is down or the maildir is missing.)
  ##
  ## Finally, be sure the source is thread-safe, since it WILL be
  ## pummelled from multiple threads at once.
  ##
  ## Examples for you to look at: mbox.rb and maildir.rb.

  bool_accessor :usual, :archived
  attr_reader :uri, :usual
  attr_accessor :id

  def initialize uri, usual=true, archived=false, id=nil
    raise ArgumentError, "id must be an integer: #{id.inspect}" unless id.is_a? Integer if id

    @uri = uri
    @usual = usual
    @archived = archived
    @id = id

    @poll_lock = Monitor.new
  end

  ## overwrite me if you have a disk incarnation
  def file_path; nil end

  def to_s; @uri.to_s; end
  def == o; o.uri == uri; end
  def is_source_for? uri; uri == @uri; end

  def read?; false; end

  ## release resources that are easy to reacquire. it is called
  ## after processing a source (e.g. polling) to prevent resource
  ## leaks (esp. file descriptors).
  def go_idle; end

  ## Returns an array containing all the labels that are natively
  ## supported by this source
  def supported_labels?; [] end

  ## Returns an array containing all the labels that are currently in
  ## the location filename
  def labels? info; [] end

  ## Yields values of the form [Symbol, Hash]
  ## add: info, labels, progress
  ## delete: info, progress
  def poll
    unimplemented
  end

  def valid? info
    true
  end

  def synchronize &block
    @poll_lock.synchronize &block
  end

  def try_lock
    acquired = @poll_lock.try_enter
    if acquired
      debug "lock acquired for: #{self}"
    else
      debug "could not acquire lock for: #{self}"
    end
    acquired
  end

  def unlock
    @poll_lock.exit
    debug "lock released for: #{self}"
  end

  ## utility method to read a raw email header from an IO stream and turn it
  ## into a hash of key-value pairs. minor special semantics for certain headers.
  ##
  ## THIS IS A SPEED-CRITICAL SECTION. Everything you do here will have a
  ## significant effect on Sup's processing speed of email from ALL sources.
  ## Little things like string interpolation, regexp interpolation, += vs <<,
  ## all have DRAMATIC effects. BE CAREFUL WHAT YOU DO!
  def self.parse_raw_email_header f
    header = {}
    last = nil

    while(line = f.gets)
      case line
      ## these three can occur multiple times, and we want the first one
      when /^(Delivered-To|X-Original-To|Envelope-To):\s*(.*?)\s*$/i; header[last = $1.downcase] ||= $2
      ## regular header: overwrite (not that we should see more than one)
      ## TODO: figure out whether just using the first occurrence changes
      ## anything (which would simplify the logic slightly)
      when /^([^:\s]+):\s*(.*?)\s*$/i; header[last = $1.downcase] = $2
      when /^\r*$/; break # blank line signifies end of header
      else
        if last
          header[last] << " " unless header[last].empty?
          header[last] << line.strip
        end
      end
    end

    %w(subject from to cc bcc).each do |k|
      v = header[k] or next
      next unless Rfc2047.is_encoded? v
      header[k] = begin
        Rfc2047.decode_to $encoding, v
      rescue Errno::EINVAL, Iconv::InvalidEncoding, Iconv::IllegalSequence => e
        #debug "warning: error decoding RFC 2047 header (#{e.class.name}): #{e.message}"
        v
      end
    end
    header
  end

protected

  ## convenience function
  def parse_raw_email_header f; self.class.parse_raw_email_header f end

  def Source.expand_filesystem_uri uri
    uri.gsub "~", File.expand_path("~")
  end
end

## if you have a @labels instance variable, include this
## to serialize them nicely as an array, rather than as a
## nasty set.
module SerializeLabelsNicely
  def before_marshal # can return an object
    c = clone
    c.instance_eval { @labels = (@labels.to_a.map { |l| l.to_s }).sort }
    c
  end

  def after_unmarshal!
    @labels = Set.new(@labels.to_a.map { |s| s.to_sym })
  end
end

class SourceManager
  include Redwood::Singleton

  def initialize
    @sources = {}
    @sources_dirty = false
    @source_mutex = Monitor.new
  end

  def [](id)
    @source_mutex.synchronize { @sources[id] }
  end

  def add_source source
    @source_mutex.synchronize do
      raise "duplicate source!" if @sources.include? source
      @sources_dirty = true
      max = @sources.max_of { |id, s| s.is_a?(DraftLoader) || s.is_a?(SentLoader) ? 0 : id }
      source.id ||= (max || 0) + 1
      ##source.id += 1 while @sources.member? source.id
      @sources[source.id] = source
    end
  end

  def sources
    ## favour the inbox by listing non-archived sources first
    @source_mutex.synchronize { @sources.values }.sort_by { |s| s.id }.partition { |s| !s.archived? }.flatten
  end

  def source_for uri
    expanded_uri = Source.expand_filesystem_uri(uri)
    sources.find { |s| s.is_source_for? expanded_uri }
  end

  def usual_sources; sources.find_all { |s| s.usual? }; end
  def unusual_sources; sources.find_all { |s| !s.usual? }; end

  def load_sources fn=Redwood::SOURCE_FN
    source_array = Redwood::load_yaml_obj(fn) || []
    @source_mutex.synchronize do
      @sources = Hash[*(source_array).map { |s| [s.id, s] }.flatten]
      @sources_dirty = false
    end
  end

  def save_sources fn=Redwood::SOURCE_FN, force=false
    @source_mutex.synchronize do
      if @sources_dirty || force
        Redwood::save_yaml_obj sources, fn, false, true
      end
      @sources_dirty = false
    end
  end
end

end
