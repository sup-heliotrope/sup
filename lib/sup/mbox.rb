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
      @expanded_uri = Source.expand_filesystem_uri(uri_or_fp)
      parts = @expanded_uri.match /^([a-zA-Z0-9]*:(\/\/)?)(.*)/
      if parts
        prefix = parts[1]
        @path = parts[3]
        uri = URI(prefix + URI.encode(@path, URI_ENCODE_CHARS))
      else
        uri = URI(URI.encode @expanded_uri, URI_ENCODE_CHARS)
        @path = uri.path
      end

      raise ArgumentError, "not an mbox uri" unless uri.scheme == "mbox"
      raise ArgumentError, "mbox URI ('#{uri}') cannot have a host: #{uri.host}" if uri.host
      raise ArgumentError, "mbox URI must have a path component" unless uri.path
      @f = nil
    else
      @f = uri_or_fp
      @path = uri_or_fp.path
      @expanded_uri = "mbox://#{URI.encode @path, URI_ENCODE_CHARS}"
    end

    super uri_or_fp, usual, archived, id
  end

  def file_path; @path end
  def is_source_for? uri; super || (uri == @expanded_uri) end

  def self.suggest_labels_for path
    ## heuristic: use the filename as a label, unless the file
    ## has a path that probably represents an inbox.
    if File.dirname(path) =~ /\b(var|usr|spool)\b/
      []
    else
      [File.basename(path).downcase.intern]
    end
  end

  def ensure_open
    @f = File.open @path, 'rb' if @f.nil?
  end
  private :ensure_open

  def go_idle
    @mutex.synchronize do
      return if @f.nil? or @path.nil?
      @f.close
      @f = nil
    end
  end

  def load_header offset
    header = nil
    @mutex.synchronize do
      ensure_open
      @f.seek offset
      header = parse_raw_email_header @f
    end
    header
  end

  def load_message offset
    @mutex.synchronize do
      ensure_open
      @f.seek offset
      begin
        ## don't use RMail::Mailbox::MBoxReader because it doesn't properly ignore
        ## "From" at the start of a message body line.
        string = ""
        until @f.eof? || MBox::is_break_line?(l = @f.gets)
          string << l
        end
        RMail::Parser.read string
      rescue RMail::Parser::Error => e
        raise FatalSourceError, "error parsing mbox file: #{e.message}"
      end
    end
  end

  def raw_header offset
    ret = ""
    @mutex.synchronize do
      ensure_open
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
    need_blank = File.exist?(@path) && !File.zero?(@path)
    File.open(@path, "ab") do |f|
      f.puts if need_blank
      f.puts "From #{from_email} #{date.asctime}"
      yield f
    end
  end

  ## apparently it's a million times faster to call this directly if
  ## we're just moving messages around on disk, than reading things
  ## into memory with raw_message.
  ##
  def each_raw_message_line offset
    @mutex.synchronize do
      ensure_open
      @f.seek offset
      until @f.eof? || MBox::is_break_line?(l = @f.gets)
        yield l
      end
    end
  end

  def default_labels
    [:inbox, :unread]
  end

  def poll
    first_offset = first_new_message
    offset = first_offset
    end_offset = File.size @f
    while offset and offset < end_offset
      yield :add,
        :info => offset,
        :labels => (labels + default_labels),
        :progress => (offset - first_offset).to_f/end_offset
      offset = next_offset offset
    end
  end

  def next_offset offset
    @mutex.synchronize do
      ensure_open
      @f.seek offset
      nil while line = @f.gets and not MBox::is_break_line? line
      offset = @f.tell
      offset != File.size(@f) ? offset : nil
    end
  end

  ## TODO optimize this by iterating over allterms list backwards or
  ## storing source_info negated
  def last_indexed_message
    benchmark(:mbox_read_index) { Index.instance.enum_for(:each_source_info, self.id).map(&:to_i).max }
  end

  ## offset of first new message or nil
  def first_new_message
    next_offset(last_indexed_message || 0)
  end

  def self.is_break_line? l
    l =~ BREAK_RE or return false
    time = $1
    begin
      ## hack -- make Time.parse fail when trying to substitute values from Time.now
      Time.parse time, Time.at(0)
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
