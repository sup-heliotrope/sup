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
  def initialize filename, end_offset=0, usual=true, archived=false, id=nil
    @filename = filename.gsub(%r(^mbox://), "")
    @end_offset = end_offset
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

  def reset!; @end_offset = 0; @dirty = true; end
  def == o; o.is_a?(Loader) && o.filename == filename; end
  def to_s; "mbox://#{@filename}"; end

  def is_source_for? s
    @filename == s || self.to_s == s
  end

  def load_header offset=nil
    header = nil
    @mutex.synchronize do
      @f.seek offset if offset
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

  ## load the full header text
  def load_header_text offset
    ret = ""
    @mutex.synchronize do
      @f.seek offset
      until @f.eof? || (l = @f.gets) =~ /^$/
        ret += l
      end
    end
    ret
  end

  def next
    return nil if done?
    @dirty = true
    next_end_offset = @end_offset

    @mutex.synchronize do
      @f.seek @end_offset

      @f.gets # skip the From separator
      next_end_offset = @f.tell
      while(line = @f.gets)
        break if line =~ BREAK_RE
        next_end_offset = @f.tell + 1
      end
    end

    start_offset = @end_offset
    @end_offset = next_end_offset

    start_offset
  end

  def each
    until @end_offset >= File.size(@f)
      n = self.next
      yield(n, labels) if n
    end
  end

  def each_header
    each { |offset, labels| yield offset, labels, load_header(offset) }
  end

  def done?; @end_offset >= File.size(@f); end 
  def total; File.size @f; end
end

Redwood::register_yaml(Loader, %w(filename end_offset usual archived id))

end
end
