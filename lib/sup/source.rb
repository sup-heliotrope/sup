module Redwood

class SourceError < StandardError; end
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
  ## - end_offset (exclusive!)
  ## - load_header offset
  ## - load_message offset
  ## - raw_header offset
  ## - raw_full_message offset
  ## - check
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

  def file_path; nil end

  def to_s; @uri.to_s; end
  def seek_to! o; self.cur_offset = o; end
  def reset!; seek_to! start_offset; end
  def == o; o.uri == uri; end
  def done?; (self.cur_offset ||= start_offset) >= end_offset; end
  def is_source_for? uri; uri == URI(uri); end

  ## check should throw a FatalSourceError or an OutOfSyncSourcError
  ## if it can detect a problem. it is called when the sup starts up
  ## to proactively notify the user of any source problems.
  def check; end

  def each
    self.cur_offset ||= start_offset
    until done?
      n, labels = self.next
      raise "no message" unless n
      yield n, labels
    end
  end

protected
  
  def Source.expand_filesystem_uri uri
    uri.gsub "~", File.expand_path("~")
  end

  def cur_offset= o
    @cur_offset = o
    @dirty = true
  end
end

end
