require 'rmail'
require 'uri'
require 'set'

module Redwood

class MBox < Source
  BREAK_RE = /^From \S+ (.+)$/

  include SerializeLabelsNicely
  yaml_properties :uri, :usual, :archived, :id, :labels

  attr_reader :labels

  ## uri_or_fp is horrific. need to refactor.
  def initialize uri_or_fp, usual=true, archived=false, id=nil, labels=nil
    @mutex = Mutex.new
    @labels = Set.new((labels || []) - LabelManager::RESERVED_LABELS)

    case uri_or_fp
    when String
      uri = URI(Source.expand_filesystem_uri(uri_or_fp))
      raise ArgumentError, "not an mbox uri" unless uri.scheme == "mbox"
      raise ArgumentError, "mbox URI ('#{uri}') cannot have a host: #{uri.host}" if uri.host
      raise ArgumentError, "mbox URI must have a path component" unless uri.path
      @f = File.open uri.path, 'rb'
      @path = uri.path
    else
      @f = uri_or_fp
      @path = uri_or_fp.path
    end

    @offset = 0
    super uri_or_fp, usual, archived, id
  end

  def file_path; @path end
  def is_source_for? uri; super || (self.uri.is_a?(String) && (URI(Source.expand_filesystem_uri(uri)) == URI(Source.expand_filesystem_uri(self.uri)))) end

  def self.suggest_labels_for path
    ## heuristic: use the filename as a label, unless the file
    ## has a path that probably represents an inbox.
    if File.dirname(path) =~ /\b(var|usr|spool)\b/
      []
    else
      [File.basename(path).downcase.intern]
    end
  end

  def load_header offset
    header = nil
    @mutex.synchronize do
      @f.seek offset
      l = @f.gets
      unless MBox::is_break_line? l
        raise OutOfSyncSourceError, "mismatch in mbox file offset #{offset.inspect}: #{l.inspect}." 
      end
      header = parse_raw_email_header @f
    end
    header
  end

  def load_message offset
    @mutex.synchronize do
      @f.seek offset
      begin
        ## don't use RMail::Mailbox::MBoxReader because it doesn't properly ignore
        ## "From" at the start of a message body line.
        string = ""
        l = @f.gets
        string << l until @f.eof? || MBox::is_break_line?(l = @f.gets)
        RMail::Parser.read string
      rescue RMail::Parser::Error => e
        raise FatalSourceError, "error parsing mbox file: #{e.message}"
      end
    end
  end

  ## scan forward until we're at the valid start of a message
  def correct_offset!
    @mutex.synchronize do
      @f.seek @offset
      string = ""
      until @f.eof? || MBox::is_break_line?(l = @f.gets)
        string << l
      end
      @offset += string.length
    end
  end

  def raw_header offset
    ret = ""
    @mutex.synchronize do
      @f.seek offset
      until @f.eof? || (l = @f.gets) =~ /^\r*$/
        ret << l
      end
    end
    ret
  end

  def raw_message offset
    ret = ""
    each_raw_message_line(offset) { |l| ret << l }
    ret
  end

  def store_message date, from_email, &block
    need_blank = File.exists?(@filename) && !File.zero?(@filename)
    File.open(@filename, "ab") do |f|
      f.puts if need_blank
      f.puts "From #{from_email} #{date.rfc2822}"
      yield f
    end
  end

  ## apparently it's a million times faster to call this directly if
  ## we're just moving messages around on disk, than reading things
  ## into memory with raw_message.
  ##
  ## i hoped never to have to move shit around on disk but
  ## sup-sync-back has to do it.
  def each_raw_message_line offset
    @mutex.synchronize do
      @f.seek offset
      yield @f.gets
      until @f.eof? || MBox::is_break_line?(l = @f.gets)
        yield l
      end
    end
  end

  def pct_done
    (@offset.to_f / File.size(@f)) * 100
  end

  def each
    end_offset = File.size @f
    while @offset < end_offset
      returned_offset = nil
      next_offset = @offset

      begin
        @mutex.synchronize do
          @f.seek @offset

          ## @offset could be at one of two places here:

          ## 1. before a \n and a mbox separator, if it was previously at
          ##    EOF and a new message was added; or,
          ## 2. at the beginning of an mbox separator (in all other
          ##    cases).

          l = @f.gets or break
          if l =~ /^\s*$/ # case 1
            returned_offset = @f.tell
            @f.gets # now we're at a BREAK_RE, so skip past it
          else # case 2
            returned_offset = @offset
            ## we've already skipped past the BREAK_RE, so just go
          end

          while(line = @f.gets)
            break if MBox::is_break_line? line
            next_offset = @f.tell
          end
        end
      rescue SystemCallError, IOError => e
        raise FatalSourceError, "Error reading #{@f.path}: #{e.message}"
      end

      @offset = next_offset
      yield returned_offset, (labels + [:unread])
    end
  end

  def next
  end

  def self.is_break_line? l
    l =~ BREAK_RE or return false
    time = $1
    begin
      ## hack -- make Time.parse fail when trying to substitute values from Time.now
      Time.parse time, 0
      true
    rescue NoMethodError, ArgumentError
      warn "found invalid date in potential mbox split line, not splitting: #{l.inspect}"
      false
    end
  end

  class Loader < self
    yaml_properties :uri, :usual, :archived, :id, :labels
  end
end
end
