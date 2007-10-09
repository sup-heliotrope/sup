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
  RE_PATTERN = /^((re|re[\[\(]\d[\]\)]):\s*)+/i

  ## some utility methods
  class << self
    def normalize_subj s; s.gsub(RE_PATTERN, ""); end
    def subj_is_reply? s; s =~ RE_PATTERN; end
    def reify_subj s; subj_is_reply?(s) ? s : "Re: " + s; end
  end

  QUOTE_PATTERN = /^\s{0,4}[>|\}]/
  BLOCK_QUOTE_PATTERN = /^-----\s*Original Message\s*----+$/
  QUOTE_START_PATTERN = /(^\s*Excerpts from)|(^\s*In message )|(^\s*In article )|(^\s*Quoting )|((wrote|writes|said|says)\s*:\s*$)/
  SIG_PATTERN = /(^-- ?$)|(^\s*----------+\s*$)|(^\s*_________+\s*$)|(^\s*--~--~-)|(^\s*--\+\+\*\*==)/

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
    if @id
      id.gsub!(/^\s+|\s+$/, "")
    else
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
        [Chunk::Text.new(error_message(@source.error.message.split("\n")))]
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
          [Chunk::Text.new(error_message(e.message))]
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

  def with_source_errors_handled
    begin
      yield
    rescue SourceError => e
      Redwood::log "problem getting messages from #{@source}: #{e.message}"
      error_message e.message
    end
  end

  def raw_header
    with_source_errors_handled { @source.raw_header @source_info }
  end

  def raw_message
    with_source_errors_handled { @source.raw_message @source_info }
  end

  ## much faster than raw_message
  def each_raw_message_line &b
    with_source_errors_handled { @source.each_raw_message_line(@source_info, &b) }
  end

  def content
    load_from_source!
    [
      from && "#{from.name} #{from.email}",
      to.map { |p| "#{p.name} #{p.email}" },
      cc.map { |p| "#{p.name} #{p.email}" },
      bcc.map { |p| "#{p.name} #{p.email}" },
      chunks.select { |c| c.is_a? Chunk::Text }.map { |c| c.lines },
      Message.normalize_subj(subj),
    ].flatten.compact.join " "
  end

  def basic_body_lines
    chunks.find_all { |c| c.is_a?(Chunk::Text) || c.is_a?(Chunk::Quote) }.map { |c| c.lines }.flatten
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

  def multipart_signed_to_chunks m
#    Redwood::log ">> multipart SIGNED: #{m.header['Content-Type']}: #{m.body.size}"
    if m.body.size != 2
      Redwood::log "warning: multipart/signed with #{m.body.size} parts (expecting 2)"
      return
    end

    payload, signature = m.body
    if signature.multipart?
      Redwood::log "warning: multipart/signed with payload multipart #{payload.multipart?} and signature multipart #{signature.multipart?}"
      return
    end

    if payload.header.content_type == "application/pgp-signature"
      Redwood::log "warning: multipart/signed with payload content type #{payload.header.content_type}"
      return
    end

    if signature.header.content_type != "application/pgp-signature"
      Redwood::log "warning: multipart/signed with signature content type #{signature.header.content_type}"
      return
    end

    [CryptoManager.verify(payload, signature), message_to_chunks(payload)].flatten.compact
  end

  def multipart_encrypted_to_chunks m
    Redwood::log ">> multipart ENCRYPTED: #{m.header['Content-Type']}: #{m.body.size}"
    if m.body.size != 2
      Redwood::log "warning: multipart/encrypted with #{m.body.size} parts (expecting 2)"
      return
    end

    control, payload = m.body
    if control.multipart?
      Redwood::log "warning: multipart/encrypted with control multipart #{control.multipart?} and payload multipart #{payload.multipart?}"
      return
    end

    if payload.header.content_type != "application/octet-stream"
      Redwood::log "warning: multipart/encrypted with payload content type #{payload.header.content_type}"
      return
    end

    if control.header.content_type != "application/pgp-encrypted"
      Redwood::log "warning: multipart/encrypted with control content type #{signature.header.content_type}"
      return
    end

    decryptedm, sig, notice = CryptoManager.decrypt payload
    children = message_to_chunks(decryptedm) if decryptedm
    [notice, sig, children].flatten.compact
  end

  def message_to_chunks m, sibling_types=[]
    if m.multipart?
      chunks =
        case m.header.content_type
        when "multipart/signed"
          multipart_signed_to_chunks m
        when "multipart/encrypted"
          multipart_encrypted_to_chunks m
        end

      unless chunks
        sibling_types = m.body.map { |p| p.header.content_type }
        chunks = m.body.map { |p| message_to_chunks p, sibling_types }.flatten.compact
      end

      chunks
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
        [Chunk::Attachment.new(m.header.content_type, filename, m, sibling_types)]

      ## otherwise, it's body text
      else
        body = Message.convert_from m.decode, m.charset
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
          chunks << Chunk::Text.new(chunk_lines) unless chunk_lines.empty?
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
            chunks << Chunk::Quote.new(chunk_lines)
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
      chunks << Chunk::Quote.new(chunk_lines) unless chunk_lines.empty?
    when :text
      chunks << Chunk::Text.new(chunk_lines) unless chunk_lines.empty?
    when :sig
      chunks << Chunk::Signature.new(chunk_lines) unless chunk_lines.empty?
    end
    chunks
  end
end

end
