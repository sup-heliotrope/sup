require 'thread'
require 'rmail'

module Redwood
module MBox

class Loader < Source
  attr_reader :labels

  def initialize uri, start_offset=nil, usual=true, archived=false, id=nil
    raise ArgumentError, "not an mbox uri" unless uri =~ %r!mbox://!
    super

    @mutex = Mutex.new
    @filename = uri.sub(%r!^mbox://!, "")
    @f = File.open @filename
    ## heuristic: use the filename as a label, unless the file
    ## has a path that probably represents an inbox.
    @labels = [:unread]
    @labels << File.basename(@filename).intern unless File.dirname(@filename) =~ /\b(var|usr|spool)\b/
  end

  def start_offset; 0; end
  def end_offset; File.size @f; end

  def load_header offset
    header = nil
    @mutex.synchronize do
      @f.seek offset
      l = @f.gets
      unless l =~ BREAK_RE
        self.broken_msg = "offset mismatch in mbox file offset #{offset.inspect}: #{l.inspect}. Run 'sup-import --rebuild #{to_s}' to correct this." 
        raise SourceError, self.broken_msg
      end
      header = MBox::read_header @f
    end
    header
  end

  def load_message offset
    @mutex.synchronize do
      @f.seek offset
      begin
        RMail::Mailbox::MBoxReader.new(@f).each_message do |input|
          return RMail::Parser.read(input)
        end
      rescue RMail::Parser::Error => e
        raise SourceError, "error parsing message with rmail: #{e.message}"
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
    returned_offset = nil
    next_offset = cur_offset

    @mutex.synchronize do
      @f.seek cur_offset

      ## cur_offset could be at one of two places here:

      ## 1. before a \n and a mbox separator, if it was previously at
      ##    EOF and a new message was added; or,
      ## 2. at the beginning of an mbox separator (in all other
      ##    cases).

      l = @f.gets or raise "next while at EOF"
      if l =~ /^\s*$/ # case 1
        returned_offset = @f.tell
        @f.gets # now we're at a BREAK_RE, so skip past it
      else # case 2
        returned_offset = cur_offset
        ## we've already skipped past the BREAK_RE, to just go
      end

      while(line = @f.gets)
        break if line =~ BREAK_RE
        next_offset = @f.tell
      end
    end

    self.cur_offset = next_offset
    [returned_offset, labels]
  end
end

Redwood::register_yaml(Loader, %w(uri cur_offset usual archived id))

end
end
