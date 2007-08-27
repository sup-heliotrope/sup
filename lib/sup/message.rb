require 'tempfile'
require 'time'
require 'iconv'

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

  HookManager.register "mime-decode", <<EOS
Executes when decoding a MIME attachment.
Variables:
  content_type: the context-type of the message
      filename: the filename of the attachment as saved to disk (generated
                on the fly, so don't call more than once)
Return value:
  The decoded text of the attachment, or nil if not decoded.
EOS
#' stupid ruby-mode

  ## some utility methods
  class << self
    def normalize_subj s; s.gsub(RE_PATTERN, ""); end
    def subj_is_reply? s; s =~ RE_PATTERN; end
    def reify_subj s; subj_is_reply?(s) ? s : "Re: " + s; end
  end

  class Attachment
    ## encoded_content is still possible MIME-encoded
    ##
    ## raw_content is after decoding but before being turned into
    ## inlineable text.
    ##
    ## lines is array of inlineable text.

    attr_reader :content_type, :filename, :lines, :raw_content

    def initialize content_type, filename, encoded_content
      @content_type = content_type
      @filename = filename
      @raw_content = encoded_content.decode
      charset = encoded_content.charset

      if @content_type =~ /^text\/plain\b/
        @lines = Message.convert_from(@raw_content, charset).split("\n")
      else
        text = HookManager.run "mime-decode", :content_type => content_type,
          :filename => lambda { write_to_disk }
        @lines = text.split("\n") if text
      end
    end

    def inlineable?; !@lines.nil? end

    def view!
      path = write_to_disk
      system "/usr/bin/run-mailcap --action=view #{@content_type}:#{path} >& /dev/null"
      $? == 0
    end
    
  private

    def write_to_disk
      file = Tempfile.new "redwood.attachment"
      file.print @raw_content
      file.close
      file.path
    end
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
  DEFAULT_SUBJECT = ""
  DEFAULT_SENDER = "(missing sender)"

  attr_reader :id, :date, :from, :subj, :refs, :replytos, :to, :source,
              :cc, :bcc, :labels, :list_address, :recipient_email, :replyto,
              :source_info, :chunks

  bool_reader :dirty, :source_marked_read

  ## if you specify a :header, will use values from that. otherwise,
  ## will try and load the header from the source.
  def initialize opts
    @source = opts[:source] or raise ArgumentError, "source can't be nil"
    @source_info = opts[:source_info] or raise ArgumentError, "source_info can't be nil"
    @snippet = opts[:snippet] || ""
    @have_snippet = !opts[:snippet].nil?
    @labels = [] + (opts[:labels] || [])
    @dirty = false
    @chunks = nil

    parse_header(opts[:header] || @source.load_header(@source_info))
  end

  def parse_header header
    header.each { |k, v| header[k.downcase] = v }

    @from = PersonManager.person_for header["from"]

    @id = header["message-id"]
    unless @id
      @id = "sup-faked-" + Digest::MD5.hexdigest(raw_header)
      Redwood::log "faking message-id for message from #@from: #@id"
    end

    date = header["date"]
    @date =
      case date
      when Time
        date
      when String
        begin
          Time.parse date
        rescue ArgumentError => e
          raise MessageFormatError, "unparsable date #{header['date']}: #{e.message}"
        end
      else
        Redwood::log "faking date header for #{@id}"
        Time.now
      end

    @subj = header.member?("subject") ? header["subject"].gsub(/\s+/, " ").gsub(/\s+$/, "") : DEFAULT_SUBJECT
    @to = PersonManager.people_for header["to"]
    @cc = PersonManager.people_for header["cc"]
    @bcc = PersonManager.people_for header["bcc"]
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
  private :parse_header

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
          parse_header @source.load_header(@source_info)
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

  ## here's where we handle decoding mime attachments. unfortunately
  ## but unsurprisingly, the world of mime attachments is a bit of a
  ## mess. as an empiricist, i'm basing the following behavior on
  ## observed mail rather than on interpretations of rfcs, so probably
  ## this will have to be tweaked.
  ##
  ## the general behavior i want is: ignore content-disposition, at
  ## least in so far as it suggests something being inline vs being an
  ## attachment. (because really, that should be the recipient's
  ## decision to make.) if a mime part is text/plain, OR if the user
  ## decoding hook converts it, then decode it and display it
  ## inline. for these decoded attachments, if it has associated
  ## filename, then make it collapsable and individually saveable;
  ## otherwise, treat it as regular body text.
  ##
  ## everything else is just an attachment and is not displayed
  ## inline.
  ##
  ## so, in contrast to mutt, the user is not exposed to the workings
  ## of the gruesome slaughterhouse and sausage factory that is a
  ## mime-encoded message, but need only see the delicious end
  ## product.
  def message_to_chunks m
    if m.multipart?
      m.body.map { |p| message_to_chunks p }.flatten.compact # recurse
    else
      filename =
        ## first, paw through the headers looking for a filename
        if m.header["Content-Disposition"] &&
            m.header["Content-Disposition"] =~ /filename="?(.*?[^\\])("|;|$)/
          $1
        elsif m.header["Content-Type"] &&
            m.header["Content-Type"] =~ /name=(.*?)(;|$)/
          $1

        ## haven't found one, but it's a non-text message. fake
        ## it.
        elsif m.header["Content-Type"] && m.header["Content-Type"] !~ /^text\/plain/
          "sup-attachment-#{Time.now.to_i}-#{rand 10000}"
        end

      ## if there's a filename, we'll treat it as an attachment.
      if filename
        [Attachment.new(m.header.content_type, filename, m)]

      ## otherwise, it's body text
      else
        body = Message.convert_from m.body, m.charset
        text_to_chunks body.normalize_whitespace.split("\n")
      end
    end
  end

  def self.convert_from body, charset
    return body unless charset

    begin
      Iconv.iconv($encoding, charset, body).join
    rescue Errno::EINVAL, Iconv::InvalidEncoding, Iconv::IllegalSequence => e
      Redwood::log "warning: error (#{e.class.name}) decoding message body from #{charset}: #{e.message}"
      File.open("sup-unable-to-decode.txt", "w") { |f| f.write body }
      body
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
