require 'time'

module Redwood

## a Message is what's threaded.
##
## it is also where the parsing for quotes and signatures is done, but
## that should be moved out to a separate class at some point (because
## i would like, for example, to be able to add in a ruby-talk
## specific module that would detect and link to /ruby-talk:\d+/
## sequences in the text of an email. (how sweet would that be?)
##
## this class catches all source exceptions. if the underlying source
## throws an error, it is caught and handled.

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
  SIG_PATTERN = /(^-- ?$)|(^\s*----------+\s*$)|(^\s*_________+\s*$)|(^\s*--~--~-)|(^\s*--\+\+\*\*==)/

  MAX_SIG_DISTANCE = 15 # lines from the end
  DEFAULT_SUBJECT = ""
  DEFAULT_SENDER = "(missing sender)"
  MAX_HEADER_VALUE_SIZE = 4096

  attr_reader :id, :date, :from, :subj, :refs, :replytos, :to, :source,
              :cc, :bcc, :labels, :attachments, :list_address, :recipient_email, :replyto,
              :source_info, :list_subscribe, :list_unsubscribe

  bool_reader :dirty, :source_marked_read, :snippet_contains_encrypted_content

  ## if you specify a :header, will use values from that. otherwise,
  ## will try and load the header from the source.
  def initialize opts
    @source = opts[:source] or raise ArgumentError, "source can't be nil"
    @source_info = opts[:source_info] or raise ArgumentError, "source_info can't be nil"
    @snippet = opts[:snippet]
    @snippet_contains_encrypted_content = false
    @have_snippet = !(opts[:snippet].nil? || opts[:snippet].empty?)
    @labels = Set.new(opts[:labels] || [])
    @dirty = false
    @encrypted = false
    @chunks = nil
    @attachments = []

    ## we need to initialize this. see comments in parse_header as to
    ## why.
    @refs = []

    #parse_header(opts[:header] || @source.load_header(@source_info))
  end

  def decode_header_field v
    return unless v
    return v unless v.is_a? String
    return unless v.size < MAX_HEADER_VALUE_SIZE # avoid regex blowup on spam
    Rfc2047.decode_to $encoding, Iconv.easy_decode($encoding, 'ASCII', v)
  end

  def parse_header encoded_header
    header = SavingHash.new { |k| decode_header_field encoded_header[k] }

    @id = if header["message-id"]
      mid = header["message-id"] =~ /<(.+?)>/ ? $1 : header["message-id"]
      sanitize_message_id mid
    else
      id = "sup-faked-" + Digest::MD5.hexdigest(raw_header)
      from = header["from"]
      #debug "faking non-existent message-id for message from #{from}: #{id}"
      id
    end

    @from = Person.from_address(if header["from"]
      header["from"]
    else
      name = "Sup Auto-generated Fake Sender <sup@fake.sender.example.com>"
      #debug "faking non-existent sender for message #@id: #{name}"
      name
    end)

    @date = case(date = header["date"])
    when Time
      date
    when String
      begin
        Time.parse date
      rescue ArgumentError => e
        #debug "faking mangled date header for #{@id} (orig #{header['date'].inspect} gave error: #{e.message})"
        Time.now
      end
    else
      #debug "faking non-existent date header for #{@id}"
      Time.now
    end

    @subj = header["subject"] ? header["subject"].gsub(/\s+/, " ").gsub(/\s+$/, "") : DEFAULT_SUBJECT
    @to = Person.from_address_list header["to"]
    @cc = Person.from_address_list header["cc"]
    @bcc = Person.from_address_list header["bcc"]

    ## before loading our full header from the source, we can actually
    ## have some extra refs set by the UI. (this happens when the user
    ## joins threads manually). so we will merge the current refs values
    ## in here.
    refs = (header["references"] || "").scan(/<(.+?)>/).map { |x| sanitize_message_id x.first }
    @refs = (@refs + refs).uniq
    @replytos = (header["in-reply-to"] || "").scan(/<(.+?)>/).map { |x| sanitize_message_id x.first }

    @replyto = Person.from_address header["reply-to"]
    @list_address = if header["list-post"]
      address = if header["list-post"] =~ /mailto:(.*?)[>\s$]/
        $1
      elsif header["list-post"] =~ /@/
        header["list-post"] # just try the whole fucking thing
      end
      address && Person.from_address(address)
    elsif header["x-mailing-list"]
      Person.from_address header["x-mailing-list"]
    end

    @recipient_email = header["envelope-to"] || header["x-original-to"] || header["delivered-to"]
    @source_marked_read = header["status"] == "RO"
    @list_subscribe = header["list-subscribe"]
    @list_unsubscribe = header["list-unsubscribe"]
  end

  ## Expected index entry format:
  ## :message_id, :subject => String
  ## :date => Time
  ## :refs, :replytos => Array of String
  ## :from => Person
  ## :to, :cc, :bcc => Array of Person
  def load_from_index! entry
    @id = entry[:message_id]
    @from = entry[:from]
    @date = entry[:date]
    @subj = entry[:subject]
    @to = entry[:to]
    @cc = entry[:cc]
    @bcc = entry[:bcc]
    @refs = (@refs + entry[:refs]).uniq
    @replytos = entry[:replytos]

    @replyto = nil
    @list_address = nil
    @recipient_email = nil
    @source_marked_read = false
    @list_subscribe = nil
    @list_unsubscribe = nil
  end

  def add_ref ref
    @refs << ref
    @dirty = true
  end

  def remove_ref ref
    @dirty = true if @refs.delete ref
  end

  attr_reader :snippet
  def is_list_message?; !@list_address.nil?; end
  def is_draft?; @source.is_a? DraftLoader; end
  def draft_filename
    raise "not a draft" unless is_draft?
    @source.fn_for_offset @source_info
  end

  ## sanitize message ids by removing spaces and non-ascii characters.
  ## also, truncate to 255 characters. all these steps are necessary
  ## to make ferret happy. of course, we probably fuck up a couple
  ## valid message ids as well. as long as we're consistent, this
  ## should be fine, though.
  ##
  ## also, mostly the message ids that are changed by this belong to
  ## spam email.
  ##
  ## an alternative would be to SHA1 or MD5 all message ids on a regular basis.
  ## don't tempt me.
  def sanitize_message_id mid; mid.gsub(/(\s|[^\000-\177])+/, "")[0..254] end

  def clear_dirty
    @dirty = false
  end

  def has_label? t; @labels.member? t; end
  def add_label l
    l = l.to_sym
    return if @labels.member? l
    @labels << l
    @dirty = true
  end
  def remove_label l
    l = l.to_sym
    return unless @labels.member? l
    @labels.delete l
    @dirty = true
  end

  def recipients
    @to + @cc + @bcc
  end

  def labels= l
    raise ArgumentError, "not a set" unless l.is_a?(Set)
    raise ArgumentError, "not a set of labels" unless l.all? { |ll| ll.is_a?(Symbol) }
    return if @labels == l
    @labels = l
    @dirty = true
  end

  def chunks
    load_from_source!
    @chunks
  end

  ## this is called when the message body needs to actually be loaded.
  def load_from_source!
    @chunks ||=
      if @source.respond_to?(:has_errors?) && @source.has_errors?
        [Chunk::Text.new(error_message(@source.error.message).split("\n"))]
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
          rmsg = @source.load_message(@source_info)
          parse_header rmsg.header
          message_to_chunks rmsg
        rescue SourceError, SocketError => e
          warn "problem getting messages from #{@source}: #{e.message}"
          ## we need force_to_top here otherwise this window will cover
          ## up the error message one
          @source.error ||= e
          Redwood::report_broken_sources :force_to_top => true
          [Chunk::Text.new(error_message(e.message).split("\n"))]
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

  ## wrap any source methods that might throw sourceerrors
  def with_source_errors_handled
    begin
      yield
    rescue SourceError => e
      warn "problem getting messages from #{@source}: #{e.message}"
      @source.error ||= e
      Redwood::report_broken_sources :force_to_top => true
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

  ## returns all the content from a message that will be indexed
  def indexable_content
    load_from_source!
    [
      from && from.indexable_content,
      to.map { |p| p.indexable_content },
      cc.map { |p| p.indexable_content },
      bcc.map { |p| p.indexable_content },
      indexable_chunks.map { |c| c.lines },
      indexable_subject,
    ].flatten.compact.join " "
  end

  def indexable_body
    indexable_chunks.map { |c| c.lines }.flatten.compact.join " "
  end

  def indexable_chunks
    chunks.select { |c| c.is_a? Chunk::Text }
  end

  def indexable_subject
    Message.normalize_subj(subj)
  end

  def quotable_body_lines
    chunks.find_all { |c| c.quotable? }.map { |c| c.lines }.flatten
  end

  def quotable_header_lines
    ["From: #{@from.full_address}"] +
      (@to.empty? ? [] : ["To: " + @to.map { |p| p.full_address }.join(", ")]) +
      (@cc.empty? ? [] : ["Cc: " + @cc.map { |p| p.full_address }.join(", ")]) +
      (@bcc.empty? ? [] : ["Bcc: " + @bcc.map { |p| p.full_address }.join(", ")]) +
      ["Date: #{@date.rfc822}",
       "Subject: #{@subj}"]
  end

  def self.build_from_source source, source_info
    m = Message.new :source => source, :source_info => source_info
    m.load_from_source!
    m
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
    if m.body.size != 2
      warn "multipart/signed with #{m.body.size} parts (expecting 2)"
      return
    end

    payload, signature = m.body
    if signature.multipart?
      warn "multipart/signed with payload multipart #{payload.multipart?} and signature multipart #{signature.multipart?}"
      return
    end

    ## this probably will never happen
    if payload.header.content_type && payload.header.content_type.downcase == "application/pgp-signature"
      warn "multipart/signed with payload content type #{payload.header.content_type}"
      return
    end

    if signature.header.content_type && signature.header.content_type.downcase != "application/pgp-signature"
      ## unknown signature type; just ignore.
      #warn "multipart/signed with signature content type #{signature.header.content_type}"
      return
    end

    [CryptoManager.verify(payload, signature), message_to_chunks(payload)].flatten.compact
  end

  def multipart_encrypted_to_chunks m
    if m.body.size != 2
      warn "multipart/encrypted with #{m.body.size} parts (expecting 2)"
      return
    end

    control, payload = m.body
    if control.multipart?
      warn "multipart/encrypted with control multipart #{control.multipart?} and payload multipart #{payload.multipart?}"
      return
    end

    if payload.header.content_type && payload.header.content_type.downcase != "application/octet-stream"
      warn "multipart/encrypted with payload content type #{payload.header.content_type}"
      return
    end

    if control.header.content_type && control.header.content_type.downcase != "application/pgp-encrypted"
      warn "multipart/encrypted with control content type #{signature.header.content_type}"
      return
    end

    notice, sig, decryptedm = CryptoManager.decrypt payload
    if decryptedm # managed to decrypt
      children = message_to_chunks(decryptedm, true)
      [notice, sig].compact + children
    else
      [notice]
    end
  end

  ## takes a RMail::Message, breaks it into Chunk:: classes.
  def message_to_chunks m, encrypted=false, sibling_types=[]
    if m.multipart?
      chunks =
        case m.header.content_type.downcase
        when "multipart/signed"
          multipart_signed_to_chunks m
        when "multipart/encrypted"
          multipart_encrypted_to_chunks m
        end

      unless chunks
        sibling_types = m.body.map { |p| p.header.content_type }
        chunks = m.body.map { |p| message_to_chunks p, encrypted, sibling_types }.flatten.compact
      end

      chunks
    elsif m.header.content_type && m.header.content_type.downcase == "message/rfc822"
      if m.body
        payload = RMail::Parser.read(m.body)
        from = payload.header.from.first ? payload.header.from.first.format : ""
        to = payload.header.to.map { |p| p.format }.join(", ")
        cc = payload.header.cc.map { |p| p.format }.join(", ")
        subj = decode_header_field(payload.header.subject) || DEFAULT_SUBJECT
        subj = Message.normalize_subj(subj.gsub(/\s+/, " ").gsub(/\s+$/, ""))
        msgdate = payload.header.date
        from_person = from ? Person.from_address(decode_header_field(from)) : nil
        to_people = to ? Person.from_address_list(decode_header_field(to)) : nil
        cc_people = cc ? Person.from_address_list(decode_header_field(cc)) : nil
        [Chunk::EnclosedMessage.new(from_person, to_people, cc_people, msgdate, subj)] + message_to_chunks(payload, encrypted)
      else
        debug "no body for message/rfc822 enclosure; skipping"
        []
      end
    elsif m.header.content_type && m.header.content_type.downcase == "application/pgp" && m.body
      ## apparently some versions of Thunderbird generate encryped email that
      ## does not follow RFC3156, e.g. messages with X-Enigmail-Version: 0.95.0
      ## they have no MIME multipart and just set the body content type to
      ## application/pgp. this handles that.
      ##
      ## TODO: unduplicate code between here and multipart_encrypted_to_chunks
      notice, sig, decryptedm = CryptoManager.decrypt m.body
      if decryptedm # managed to decrypt
        children = message_to_chunks decryptedm, true
        [notice, sig].compact + children
      else
        [notice]
      end
    else
      filename =
        ## first, paw through the headers looking for a filename
        if m.header["Content-Disposition"] && m.header["Content-Disposition"] =~ /filename="?(.*?[^\\])("|;|$)/
          $1
        elsif m.header["Content-Type"] && m.header["Content-Type"] =~ /name="?(.*?[^\\])("|;|$)/i
          $1

        ## haven't found one, but it's a non-text message. fake
        ## it.
        ##
        ## TODO: make this less lame.
        elsif m.header["Content-Type"] && m.header["Content-Type"] !~ /^text\/plain/i
          extension =
            case m.header["Content-Type"]
            when /text\/html/ then "html"
            when /image\/(.*)/ then $1
            end

          ["sup-attachment-#{Time.now.to_i}-#{rand 10000}", extension].join(".")
        end

      ## if there's a filename, we'll treat it as an attachment.
      if filename
        ## filename could be 2047 encoded
        filename = Rfc2047.decode_to $encoding, filename
        # add this to the attachments list if its not a generated html
        # attachment (should we allow images with generated names?).
        # Lowercase the filename because searches are easier that way 
        @attachments.push filename.downcase unless filename =~ /^sup-attachment-/
        add_label :attachment unless filename =~ /^sup-attachment-/
        content_type = (m.header.content_type || "application/unknown").downcase # sometimes RubyMail gives us nil
        [Chunk::Attachment.new(content_type, filename, m, sibling_types)]

      ## otherwise, it's body text
      else
        ## if there's no charset, use the current encoding as the charset.
        ## this ensures that the body is normalized to avoid non-displayable
        ## characters
        body = Iconv.easy_decode($encoding, m.charset || $encoding, m.decode) if m.body
        text_to_chunks((body || "").normalize_whitespace.split("\n"), encrypted)
      end
    end
  end

  ## parse the lines of text into chunk objects.  the heuristics here
  ## need tweaking in some nice manner. TODO: move these heuristics
  ## into the classes themselves.
  def text_to_chunks lines, encrypted
    state = :text # one of :text, :quote, or :sig
    chunks = []
    chunk_lines = []

    lines.each_with_index do |line, i|
      nextline = lines[(i + 1) ... lines.length].find { |l| l !~ /^\s*$/ } # skip blank lines

      case state
      when :text
        newstate = nil

        ## the following /:$/ followed by /\w/ is an attempt to detect the
        ## start of a quote. this is split into two regexen because the
        ## original regex /\w.*:$/ had very poor behavior on long lines
        ## like ":a:a:a:a:a" that occurred in certain emails.
        if line =~ QUOTE_PATTERN || (line =~ /:$/ && line =~ /\w/ && nextline =~ QUOTE_PATTERN)
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

        if line =~ QUOTE_PATTERN || (line =~ /^\s*$/ && nextline =~ QUOTE_PATTERN)
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
        @snippet ||= ""
        @snippet += " " unless @snippet.empty?
        @snippet += line.gsub(/^\s+/, "").gsub(/[\r\n]/, "").gsub(/\s+/, " ")
        @snippet = @snippet[0 ... SNIPPET_LEN].chomp
        @dirty = true unless encrypted && $config[:discard_snippets_from_encrypted_messages]
        @snippet_contains_encrypted_content = true if encrypted
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
