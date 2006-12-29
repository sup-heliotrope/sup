module Redwood

class SourceError < StandardError; end

class Source
  ## dirty? described whether cur_offset has changed, which means the
  ## source needs to be re-saved to disk.
  ##
  ## broken? means no message can be loaded, e.g. IMAP server is
  ## down, mbox file is corrupt and needs to be rescanned.
  bool_reader :usual, :archived, :dirty
  attr_reader :cur_offset, :broken_msg
  attr_accessor :id

  ## You should implement:
  ##
  ## start_offset
  ## end_offset
  ## load_header(offset)
  ## load_message(offset)
  ## raw_header(offset)
  ## raw_full_message(offset)
  ## next

  def initialize uri, initial_offset=nil, usual=true, archived=false, id=nil
    @uri = uri
    @cur_offset = initial_offset || start_offset
    @usual = usual
    @archived = archived
    @id = id
    @dirty = false
    @broken_msg = nil
  end

  def broken?; !@broken_msg.nil?; end
  def to_s; @uri; end
  def seek_to! o; self.cur_offset = o; end
  def reset!; seek_to! start_offset; end
  def == o; o.to_s == to_s; end
  def done?; cur_offset >= end_offset; end 
  def is_source_for? s; to_s == s; end

  def each
    until done?
      n, labels = self.next
      raise "no message" unless n
      yield n, labels
    end
  end

protected

  def cur_offset= o
    @cur_offset = o
    @dirty = true
  end
  
  attr_writer :broken_msg
end

Redwood::register_yaml(Source, %w(uri cur_offset usual archived id))

end
