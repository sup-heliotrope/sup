require 'rmail'

module Redwood
module MBox

class Loader < Source
  attr_reader_cloned :labels

  def initialize uri_or_fp, start_offset=nil, usual=true, archived=false, id=nil
    super

    @mutex = Mutex.new
    @labels = [:unread]
    @labels << :inbox unless archived?

    case uri_or_fp
    when String
      raise ArgumentError, "not an mbox uri" unless uri_or_fp =~ %r!mbox://!

      fn = uri_or_fp.sub(%r!^mbox://!, "")
      ## heuristic: use the filename as a label, unless the file
      ## has a path that probably represents an inbox.
      @labels << File.basename(fn).intern unless File.dirname(fn) =~ /\b(var|usr|spool)\b/
      @f = File.open fn
    else
      @f = uri_or_fp
    end
  end

  def start_offset; 0; end
  def end_offset; File.size @f; end
  def pct_done; 100.0 * cur_offset.to_f / end_offset.to_f; end

  def load_header offset
    header = nil
    @mutex.synchronize do
      @f.seek offset
      l = @f.gets
      unless l =~ BREAK_RE
        Redwood::log "#{to_s}: offset mismatch in mbox file offset #{offset.inspect}: #{l.inspect}"
        self.broken_msg = "offset mismatch in mbox file offset #{offset.inspect}: #{l.inspect}. Run 'sup-import --rebuild #{to_s}' to correct this." 
        raise SourceError, self.broken_msg
      end
      header = MBox::read_header @f
    end
    header
  end

  def load_message offset
    raise SourceError, self.broken_msg if broken?
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
    raise SourceError, self.broken_msg if broken?
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
    raise SourceError, self.broken_msg if broken?
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
    raise SourceError, self.broken_msg if broken?
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
