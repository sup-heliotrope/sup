module Redwood

class SourceError < StandardError; end

class Source
  ## Implementing a new source is typically quite easy, because Sup
  ## only needs to be able to:
  ##  1. See how many messages it contains
  ##  2. Get an arbirtrary message
  ##  3. (optional) see whether the source has marked it read or not
  ##
  ## In particular, Sup doesn't need to move messages, mark them as
  ## read, delete them, or anything else. (Well, at some point it will
  ## need to delete them, but that will be an optional capability.)
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
  ## - end_offset (exclusive!)
  ## - load_header offset
  ## - load_message offset
  ## - raw_header offset
  ## - raw_full_message offset
  ## - next (or each, if you prefer)
  ##
  ## ... where "offset" really means unique id. (You can tell I
  ## started with mbox.)
  ##
  ## You can throw SourceErrors from any of those, but we don't catch
  ## anything else, so make sure you catch *all* errors and reraise
  ## them as SourceErrors, and set broken_msg to something if the
  ## source needs to be rescanned.
  ##
  ## Also, be sure to make the source thread-safe, since it WILL be
  ## pummeled from multiple threads at once.
  ##
  ## Two examples for you to look at, though sadly neither of them is
  ## as simple as I'd like: mbox/loader.rb and imap.rb



  ## dirty? described whether cur_offset has changed, which means the
  ## source info needs to be re-saved to sources.yaml.
  ##
  ## broken? means no message can be loaded, e.g. IMAP server is
  ## down, mbox file is corrupt and needs to be rescanned, etc.
  bool_reader :usual, :archived, :dirty
  attr_reader :uri, :cur_offset, :broken_msg
  attr_accessor :id

  def initialize uri, initial_offset=nil, usual=true, archived=false, id=nil
    @uri = uri
    @cur_offset = initial_offset
    @usual = usual
    @archived = archived
    @id = id
    @dirty = false
    @broken_msg = nil
  end

  def broken?; !@broken_msg.nil?; end
  def to_s; @uri.to_s; end
  def seek_to! o; self.cur_offset = o; end
  def reset!
    return if broken?
    begin
      seek_to! start_offset
    rescue SourceError
    end
  end
  def == o; o.to_s == to_s; end
  def done?;
    return true if broken? 
    begin
      (self.cur_offset ||= start_offset) >= end_offset
    rescue SourceError => e
      true
    end
  end
  def is_source_for? uri; URI(self.uri) == URI(uri); end

  def each
    return if broken?
    begin
      self.cur_offset ||= start_offset
      until done? || broken? # just like life!
        n, labels = self.next
        raise "no message" unless n
        yield n, labels
      end
    rescue SourceError => e
      self.broken_msg = e.message
    end
  end

protected
  
  def cur_offset= o
    @cur_offset = o
    @dirty = true
  end

  def broken_msg= m
    @broken_msg = m
#    Redwood::log "#{to_s}: #{m}"
  end
end

Redwood::register_yaml(Source, %w(uri cur_offset usual archived id))

end
