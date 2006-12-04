require 'thread'
require 'rmail'

module Redwood
module MBox

class Error < StandardError; end

class Loader
  attr_reader :filename
  bool_reader :usual, :archived, :read, :dirty
  attr_accessor :id, :labels

  ## end_offset is the last offsets within the file which we've read.
  ## everything after that is considered new messages that haven't
  ## been indexed.
  def initialize filename, end_offset=nil, usual=true, archived=false, id=nil
    @filename = filename.gsub(%r(^mbox://), "")
    @end_offset = end_offset || 0
    @dirty = false
    @usual = usual
    @archived = archived
    @id = id
    @mutex = Mutex.new
    @f = File.open @filename
    @labels = ([
      :unread,
      archived ? nil : :inbox,
    ] +
      if File.dirname(filename) =~ /\b(var|usr|spool)\b/
        []
      else
        [File.basename(filename).intern] 
      end).compact
  end

  def seek_to! offset
    @end_offset = [offset, File.size(@f) - 1].min;
    @dirty = true
  end
  def reset!; seek_to! 0; end
  def == o; o.is_a?(Loader) && o.filename == filename; end
  def to_s; "mbox://#{@filename}"; end

  def is_source_for? s
    @filename == s || self.to_s == s
  end

  def load_header offset=nil
    header = nil
    @mutex.synchronize do
      @f.seek offset if offset
      l = @f.gets
      raise Error, "offset mismatch in mbox file: #{l.inspect}. Run 'sup-import --rebuild #{to_s}' to correct this." unless l =~ BREAK_RE
      header = MBox::read_header @f
    end
    header
  end

  def load_message offset
    ret = nil
    @mutex.synchronize do
      @f.seek offset
      RMail::Mailbox::MBoxReader.new(@f).each_message do |input|
        return RMail::Parser.read(input)
      end
    end
  end

  def raw_header offset
    ret = ""
    @mutex.synchronize do
      @f.seek offset
      until @f.eof? || (l = @f.gets) =~ /^$/
        ret += l
      end
    end
    ret
  end

  def raw_full_message offset
    ret = ""
    @mutex.synchronize do
      @f.seek offset
      @f.gets # skip mbox header
      until @f.eof? || (l = @f.gets) =~ BREAK_RE
        ret += l
      end
    end
    ret
  end

  def next
    return nil if done?
    @dirty = true
    start_offset = nil
    next_end_offset = @end_offset

    ## @end_offset could be at one of two places here: before a \n and
    ## a mbox separator, if it was previously at EOF and a new message
    ## was added; or, at the beginning of an mbox separator (in all
    ## other cases).
    @mutex.synchronize do
      @f.seek @end_offset
      l = @f.gets or return nil
      if l =~ /^\s*$/
        start_offset = @f.tell
        @f.gets
      else
        start_offset = @end_offset
      end

      while(line = @f.gets)
        break if line =~ BREAK_RE
        next_end_offset = @f.tell
      end
    end

    @end_offset = next_end_offset
    start_offset
  end

  def each
    until @end_offset >= File.size(@f)
      n = self.next
      yield(n, labels) if n
    end
  end

  def done?; @end_offset >= File.size(@f); end 
  def total; File.size @f; end
end

Redwood::register_yaml(Loader, %w(filename end_offset usual archived id))

end
end
