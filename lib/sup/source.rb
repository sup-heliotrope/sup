module Redwood

class SourceError < StandardError; end

class Source
  ## dirty? described whether cur_offset has changed, which means the
  ## source needs to be re-saved to disk.
  ##
  ## broken? means no message can be loaded, e.g. IMAP server is
  ## down, mbox file is corrupt and needs to be rescanned.

  ## When writing a new source, you should implement:
  ##
  ## start_offset
  ## end_offset
  ## load_header(offset)
  ## load_message(offset)
  ## raw_header(offset)
  ## raw_full_message(offset)
  ## next (or each, if you prefer)

  ## you can throw SourceErrors from any of those, but we don't catch
  ## anything else, so make sure you catch all non-fatal errors and
  ## reraise them as source errors.

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
  def to_s; @uri; end
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
  def is_source_for? s; to_s == s; end

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
