require 'rmail'
require 'uri'

module Redwood
module MBox

class Loader < Source
  yaml_properties :uri, :cur_offset, :usual, :archived, :id
  def initialize uri_or_fp, start_offset=nil, usual=true, archived=false, id=nil
    super

    @mutex = Mutex.new
    @labels = [:unread]

    case uri_or_fp
    when String
      uri = URI(uri_or_fp)
      raise ArgumentError, "not an mbox uri" unless uri.scheme == "mbox"
      raise ArgumentError, "mbox uri ('#{uri}') cannot have a host: #{uri.host}" if uri.host
      ## heuristic: use the filename as a label, unless the file
      ## has a path that probably represents an inbox.
      @labels << File.basename(uri.path).intern unless File.dirname(uri.path) =~ /\b(var|usr|spool)\b/
      @f = File.open uri.path
    else
      @f = uri_or_fp
    end
  end

  def check
    if (cur_offset ||= start_offset) > end_offset
      raise OutOfSyncSourceError, "mbox file is smaller than last recorded message offset. Messages have probably been deleted by another client."
    end
  end
    
  def start_offset; 0; end
  def end_offset; File.size @f; end

  def load_header offset
    header = nil
    @mutex.synchronize do
      @f.seek offset
      l = @f.gets
      unless l =~ BREAK_RE
        raise OutOfSyncSourceError, "mismatch in mbox file offset #{offset.inspect}: #{l.inspect}." 
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
        raise FatalSourceError, "error parsing mbox file: #{e.message}"
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
    each_raw_full_message_line(offset) { |l| ret += l }
    ret
  end

  ## apparently it's a million times faster to call this directly if
  ## we're just moving messages around on disk, than reading things
  ## into memory with raw_full_message.
  ##
  ## i hoped never to have to move shit around on disk but
  ## sup-sync-back has to do it.
  def each_raw_full_message_line offset
    @mutex.synchronize do
      @f.seek offset
      yield @f.gets
      until @f.eof? || (l = @f.gets) =~ BREAK_RE
        yield l
      end
    end
  end

  def next
    returned_offset = nil
    next_offset = cur_offset

    begin
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
          ## we've already skipped past the BREAK_RE, so just go
        end

        while(line = @f.gets)
          break if line =~ BREAK_RE
          next_offset = @f.tell
        end
      end
    rescue SystemCallError, IOError => e
      raise FatalSourceError, "Error reading #{@f.path}: #{e.message}"
    end

    self.cur_offset = next_offset
    [returned_offset, @labels.clone]
  end
end

end
end
