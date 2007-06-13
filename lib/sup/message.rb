require 'tempfile'
require 'time'

module Redwood

class MessageFormatError < StandardError; end

## a Message is what's threaded.
##
## it is also where the parsing for quotes and signatures is done, but
## that should be moved out to a separate class at some point (because
## i would like, for example, to be able to add in a ruby-talk
## specific module that would detect and link to /ruby-talk:\d+/
## sequences in the text of an email. (how sweet would that be?)
class Message
  SNIPPET_LEN = 80
  WRAP_LEN = 80 # wrap at this width
  RE_PATTERN = /^((re|re[\[\(]\d[\]\)]):\s*)+/i
    
  ## some utility methods
  class << self
    def normalize_subj s; s.gsub(RE_PATTERN, ""); end
    def subj_is_reply? s; s =~ RE_PATTERN; end
    def reify_subj s; subj_is_reply?(s) ? s : "Re: " + s; end
  end

  class Attachment
    attr_reader :content_type, :desc, :filename
    def initialize content_type, desc, part
      @content_type = content_type
      @desc = desc
      @part = part
      @file = nil
      desc =~ /filename="?(.*?)("|$)/ && @filename = $1
    end

    def view!
      unless @file
        @file = Tempfile.new "redwood.attachment"
        @file.print self
        @file.close
      end

      system "/usr/bin/run-mailcap --action=view #{@content_type}:#{@file.path} >& /dev/null"
      $? == 0
    end

    def to_s; @part.decode; end
  end

  class Text
    attr_reader :lines
    def initialize lines
      ## do some wrapping
      @lines = lines.map { |l| l.chomp.wrap WRAP_LEN }.flatten
    end
  end

  class Quote
    attr_reader :lines
    def initialize lines
      @lines = lines
    end
  end

  class Signature
    attr_reader :lines
    def initialize lines
      @lines = lines
    end
  end


  QUOTE_PATTERN = /^\s{0,4}[>|\}]/
  BLOCK_QUOTE_PATTERN = /^-----\s*Original Message\s*----+$/
  QUOTE_START_PATTERN = /(^\s*Excerpts from)|(^\s*In message )|(^\s*In article )|(^\s*Quoting )|((wrote|writes|said|says)\s*:\s*$)/
  SIG_PATTERN = /(^-- ?$)|(^\s*----------+\s*$)|(^\s*_________+\s*$)|(^\s*--~--~-)/

  MAX_SIG_DISTANCE = 15 # lines from the end
  DEFAULT_SUBJECT = "(missing subject)"
  DEFAULT_SENDER = "(missing sender)"

  attr_reader :id, :date, :from, :subj, :refs, :replytos, :to, :source,
              :cc, :bcc, :labels, :list_address, :recipient_email, :replyto,
              :source_info, :chunks

  bool_reader :dirty, :source_marked_read

  ## if you specify a :header, will use values from that. otherwise, will try and
  ## load the header from the source.
  def initialize opts
    @source = opts[:source] or raise ArgumentError, "source can't be nil"
    @source_info = opts[:source_info] or raise ArgumentError, "source_info can't be nil"
    @snippet = opts[:snippet] || ""
    @have_snippet = !opts[:snippet].nil?
    @labels = [] + (opts[:labels] || [])
    @dirty = false
    @chunks = nil

    read_header(opts[:header] || @source.load_header(@source_info))
  end

  def read_header header
    header.each { |k, v| header[k.downcase] = v }

    %w(message-id date).each do |f|
      raise MessageFormatError, "no #{f} field in header #{header.inspect} (source #@source offset #@source_info)" unless header.include? f
      raise MessageFormatError, "nil #{f} field in header #{header.inspect} (source #@source offset #@source_info)" unless header[f]
    end

    begin
      date = header["date"]
      @date = Time === date ? date : Time.parse(header["date"])
    rescue ArgumentError => e
      raise MessageFormatError, "unparsable date #{header['date']}: #{e.message}"
    end

    @subj = header.member?("subject") ? header["subject"].gsub(/\s+/, " ").gsub(/\s+$/, "") : DEFAULT_SUBJECT
    @from = PersonManager.person_for header["from"]
    @to = PersonManager.people_for header["to"]
    @cc = PersonManager.people_for header["cc"]
    @bcc = PersonManager.people_for header["bcc"]
    @id = header["message-id"]
    @refs = (header["references"] || "").gsub(/[<>]/, "").split(/\s+/).flatten
    @replytos = (header["in-reply-to"] || "").scan(/<(.*?)>/).flatten
    @replyto = PersonManager.person_for header["reply-to"]
    @list_address =
      if header["list-post"]
        @list_address = PersonManager.person_for header["list-post"].gsub(/^<mailto:|>$/, "")
      else
        nil
      end

    @recipient_email = header["envelope-to"] || header["x-original-to"] || header["delivered-to"]
    @source_marked_read = header["status"] == "RO"
  end
  private :read_header

  def snippet; @snippet || chunks && @snippet; end
  def is_list_message?; !@list_address.nil?; end
  def is_draft?; @source.is_a? DraftLoader; end
  def draft_filename
    raise "not a draft" unless is_draft?
    @source.fn_for_offset @source_info
  end

  def save index
    index.sync_message self if @dirty
    @dirty = false
  end

  def has_label? t; @labels.member? t; end
  def add_label t
    return if @labels.member? t
    @labels.push t
    @dirty = true
  end
  def remove_label t
    return unless @labels.member? t
    @labels.delete t
    @dirty = true
  end

  def recipients
    @to + @cc + @bcc
  end

  def labels= l
    @labels = l
    @dirty = true
  end

  ## this is called when the message body needs to actually be loaded.
  def load_from_source!
    @chunks ||=
      if @source.has_errors?
        [Text.new(error_message(@source.error.message.split("\n")))]
      else
        begin
          ## we need to re-read the header because it contains information
          ## that we don't store in the index. actually i think it's just
          ## the mailing list address (if any), so this is kinda overkill.
          ## i could just store that in the index, but i think there might
          ## be other things like that in the future, and i'd rather not
          ## bloat the index.
          ## actually, it's also the differentiation between to/cc/bcc,
          ## so i will keep this.
          read_header @source.load_header(@source_info)
          message_to_chunks @source.load_message(@source_info)
        rescue SourceError, SocketError, MessageFormatError => e
          Redwood::log "problem getting messages from #{@source}: #{e.message}"
          ## we need force_to_top here otherwise this window will cover
          ## up the error message one
          Redwood::report_broken_sources :force_to_top => true
          [Text.new(error_message(e.message))]
        end
      end
  end

  def error_message msg
    <<EOS
#@snippet...

***********************************************************************
 An error occurred while loading this message. It is possible that
 the source has changed, or (in the case of remote sources) is down.
 You can check the log for errors, though hopefully an error window
 should have popped up at some point.

 The message location was:
 #@source##@source_info
***********************************************************************

The error message was:
  #{msg}
EOS
  end

  def raw_header
    begin
      @source.raw_header @source_info
    rescue SourceError => e
      Redwood::log "problem getting messages from #{@source}: #{e.message}"
      error_message e.message
    end
  end

  def raw_full_message
    begin
      @source.raw_full_message @source_info
    rescue SourceError => e
      Redwood::log "problem getting messages from #{@source}: #{e.message}"
      error_message(e.message)
    end
  end

  def content
    load_from_source!
    [
      from && "#{from.name} #{from.email}",
      to.map { |p| "#{p.name} #{p.email}" },
      cc.map { |p| "#{p.name} #{p.email}" },
      bcc.map { |p| "#{p.name} #{p.email}" },
      chunks.select { |c| c.is_a? Text }.map { |c| c.lines },
      Message.normalize_subj(subj),
    ].flatten.compact.join " "
  end

  def basic_body_lines
    chunks.find_all { |c| c.is_a?(Text) || c.is_a?(Quote) }.map { |c| c.lines }.flatten
  end

  def basic_header_lines
    ["From: #{@from.full_address}"] +
      (@to.empty? ? [] : ["To: " + @to.map { |p| p.full_address }.join(", ")]) +
      (@cc.empty? ? [] : ["Cc: " + @cc.map { |p| p.full_address }.join(", ")]) +
      (@bcc.empty? ? [] : ["Bcc: " + @bcc.map { |p| p.full_address }.join(", ")]) +
      ["Date: #{@date.rfc822}",
       "Subject: #{@subj}"]
  end

private

  ## (almost) everything rmail-specific goes here
  def message_to_chunks m
    if m.multipart?
      m.body.map { |p| message_to_chunks p }.flatten.compact
    else
      case m.header.content_type
      when "text/plain", nil
        m.body && body = m.decode or raise MessageFormatError, "For some bizarre reason, RubyMail was unable to parse this message."
        text_to_chunks(body.normalize_whitespace.split("\n"))
      when /^multipart\//
        []
      else
        disp = m.header["Content-Disposition"] || ""
        [Attachment.new(m.header.content_type, disp.gsub(/[\s\n]+/, " "), m)]
      end
    end
  end

  ## parse the lines of text into chunk objects.  the heuristics here
  ## need tweaking in some nice manner. TODO: move these heuristics
  ## into the classes themselves.
  def text_to_chunks lines
    state = :text # one of :text, :quote, or :sig
    chunks = []
    chunk_lines = []

    lines.each_with_index do |line, i|
      nextline = lines[(i + 1) ... lines.length].find { |l| l !~ /^\s*$/ } # skip blank lines

      case state
      when :text
        newstate = nil

        if line =~ QUOTE_PATTERN || (line =~ QUOTE_START_PATTERN && (nextline =~ QUOTE_PATTERN || nextline =~ QUOTE_START_PATTERN))
          newstate = :quote
        elsif line =~ SIG_PATTERN && (lines.length - i) < MAX_SIG_DISTANCE
          newstate = :sig
        elsif line =~ BLOCK_QUOTE_PATTERN
          newstate = :block_quote
        end

        if newstate
          chunks << Text.new(chunk_lines) unless chunk_lines.empty?
          chunk_lines = [line]
          state = newstate
        else
          chunk_lines << line
        end

      when :quote
        newstate = nil

        if line =~ QUOTE_PATTERN || line =~ QUOTE_START_PATTERN #|| line =~ /^\s*$/
          chunk_lines << line
        elsif line =~ SIG_PATTERN && (lines.length - i) < MAX_SIG_DISTANCE
          newstate = :sig
        else
          newstate = :text
        end

        if newstate
          if chunk_lines.empty?
            # nothing
          else
            chunks << Quote.new(chunk_lines)
          end
          chunk_lines = [line]
          state = newstate
        end

      when :block_quote, :sig
        chunk_lines << line
      end
 
      if !@have_snippet && state == :text && (@snippet.nil? || @snippet.length < SNIPPET_LEN) && line !~ /[=\*#_-]{3,}/ && line !~ /^\s*$/
        @snippet += " " unless @snippet.empty?
        @snippet += line.gsub(/^\s+/, "").gsub(/[\r\n]/, "").gsub(/\s+/, " ")
        @snippet = @snippet[0 ... SNIPPET_LEN].chomp
      end
    end

    ## final object
    case state
    when :quote, :block_quote
      chunks << Quote.new(chunk_lines) unless chunk_lines.empty?
    when :text
      chunks << Text.new(chunk_lines) unless chunk_lines.empty?
    when :sig
      chunks << Signature.new(chunk_lines) unless chunk_lines.empty?
    end
    chunks
  end
end

end
