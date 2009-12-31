require "sup/rfc2047"

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
  ## On the other hand, Sup assumes that you can assign each message a
  ## unique integer id, such that newer messages have higher ids than
  ## earlier ones, and that those ids stay constant across sessions
  ## (in the absence of some other client going in and fucking
  ## everything up). For example, for mboxes I use the file offset of
  ## the start of the message. If a source does NOT have that
  ## capability, e.g. IMAP, then you have to do a little more work to
  ## simulate it.
  ##
  ## To write a new source, subclass this class, and implement:
  ##
  ## - start_offset
  ## - end_offset (exclusive!) (or, #done?)
  ## - load_header offset
  ## - load_message offset
  ## - raw_header offset
  ## - raw_message offset
  ## - check (optional)
  ## - next (or each, if you prefer): should return a message and an
  ##   array of labels.
  ##
  ## ... where "offset" really means unique id. (You can tell I
  ## started with mbox.)
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
  ## Examples for you to look at: mbox/loader.rb, imap.rb, and
  ## maildir.rb.

  ## let's begin!
  ##
  ## dirty? means cur_offset has changed, so the source info needs to
  ## be re-saved to sources.yaml.
  bool_reader :usual, :archived, :dirty
  attr_reader :uri, :cur_offset
  attr_accessor :id

  def initialize uri, initial_offset=nil, usual=true, archived=false, id=nil
    raise ArgumentError, "id must be an integer: #{id.inspect}" unless id.is_a? Fixnum if id

    @uri = uri
    @cur_offset = initial_offset
    @usual = usual
    @archived = archived
    @id = id
    @dirty = false
  end

  ## overwrite me if you have a disk incarnation (currently used only for sup-sync-back)
  def file_path; nil end

  def to_s; @uri.to_s; end
  def seek_to! o; self.cur_offset = o; end
  def reset!; seek_to! start_offset; end
  def == o; o.uri == uri; end
  def done?; start_offset.nil? || (self.cur_offset ||= start_offset) >= end_offset; end
  def is_source_for? uri; uri == @uri; end

  ## check should throw a FatalSourceError or an OutOfSyncSourcError
  ## if it can detect a problem. it is called when the sup starts up
  ## to proactively notify the user of any source problems.
  def check; end

  ## yields successive offsets and labels, starting at #cur_offset.
  ##
  ## when implementing a source, you can overwrite either #each or #next. the
  ## default #each just calls next over and over.
  def each
    self.cur_offset ||= start_offset
    until done?
      offset, labels = self.next
      yield offset, labels
    end
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

  def cur_offset= o
    @cur_offset = o
    @dirty = true
  end
end

## if you have a @labels instance variable, include this
## to serialize them nicely as an array, rather than as a
## nasty set.
module SerializeLabelsNicely
  def before_marshal # can return an object
    c = clone
    c.instance_eval { @labels = @labels.to_a.map { |l| l.to_s } }
    c
  end

  def after_unmarshal!
    @labels = Set.new(@labels.map { |s| s.to_sym })
  end
end

class SourceManager
  include Singleton

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

  def source_for uri; sources.find { |s| s.is_source_for? uri }; end
  def usual_sources; sources.find_all { |s| s.usual? }; end
  def unusual_sources; sources.find_all { |s| !s.usual? }; end

  def load_sources fn=Redwood::SOURCE_FN
    source_array = (Redwood::load_yaml_obj(fn) || []).map { |o| Recoverable.new o }
    @source_mutex.synchronize do
      @sources = Hash[*(source_array).map { |s| [s.id, s] }.flatten]
      @sources_dirty = false
    end
  end

  def save_sources fn=Redwood::SOURCE_FN
    @source_mutex.synchronize do
      if @sources_dirty || @sources.any? { |id, s| s.dirty? }
        bakfn = fn + ".bak"
        if File.exists? fn
          File.chmod 0600, fn
          FileUtils.mv fn, bakfn, :force => true unless File.exists?(bakfn) && File.size(fn) == 0
        end
        Redwood::save_yaml_obj sources, fn, true
        File.chmod 0600, fn
      end
      @sources_dirty = false
    end
  end
end

end
