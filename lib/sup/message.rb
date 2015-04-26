# encoding: UTF-8

require 'time'
require 'uri'


module Redwood

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
  SIG_PATTERN = /(^(- )*-- ?$)|(^\s*----------+\s*$)|(^\s*_________+\s*$)|(^\s*--~--~-)|(^\s*--\+\+\*\*==)/

  GPG_SIGNED_START = "-----BEGIN PGP SIGNED MESSAGE-----"
  GPG_SIGNED_END = "-----END PGP SIGNED MESSAGE-----"
  GPG_START = "-----BEGIN PGP MESSAGE-----"
  GPG_END = "-----END PGP MESSAGE-----"
  GPG_SIG_START = "-----BEGIN PGP SIGNATURE-----"
  GPG_SIG_END = "-----END PGP SIGNATURE-----"

  MAX_SIG_DISTANCE = 15 # lines from the end
  DEFAULT_SUBJECT = ""
  DEFAULT_SENDER = "(missing sender)"
  MAX_HEADER_VALUE_SIZE = 4096

  attr_reader :id, :date, :from, :subj, :refs, :replytos, :to,
              :cc, :bcc, :labels, :attachments, :list_address, :recipient_email, :replyto,
              :list_subscribe, :list_unsubscribe

  bool_reader :dirty, :source_marked_read, :snippet_contains_encrypted_content

  attr_accessor :locations

  ## if you specify a :header, will use values from that. otherwise,
  ## will try and load the header from the source.
  def initialize opts
    @locations = opts[:locations] or raise ArgumentError, "locations can't be nil"
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
    @date = nil # may or may not have been set when the message was loaded
                # or discovered for the first time.
    @id   = nil # same as @date for invalid ids
    @refs = []

    #parse_header(opts[:header] || @source.load_header(@source_info))
  end

  def parse_header m
    # load
    # @id   sanitized message id
    # @from
    # @date
    # @subj
    # @to
    # @cc
    # @bcc
    # @refs
    # @replyto
    # @replytos
    # @list_address
    # @receipient_email
    # @source_marked_read
    # @list_subscribe
    # @list_unsubscribe

    unless m.message_id
      m.message_id =  @id || "<#{Time.now.to_i}-defaulted-#{Digest::MD5.hexdigest m.header.to_s}@sup-faked>"
      debug "Using fake id (newly created or existing): #{id} for message located at: #{location.inspect}."
    end

    @id = sanitize_message_id m.message_id

    @from = Person.from_address m.fetch_header(:from)
    @from = Person.from_address "Sup Auto-generated Fake Sender <sup@fake.sender.example.com>" unless @from
    @sender = Person.from_address m.fetch_header(:sender)

    begin
      if m.date
        @date = m.date.to_time
      else
        warn "Invalid date for message #{@id}, using 'now' or previously fake 'now'."
        BufferManager.flash "Invalid date for message #{@id}, using 'now' or previously fake 'now'." if BufferManager.instantiated?
        @date = @date || Time.now.to_time
      end
    rescue NoMethodError
      # TODO: remove this rescue once mail/#564 is fixed
      warn "Invalid date for message #{@id}, using 'now' or previously fake 'now'."
      BufferManager.flash "Invalid date for message #{@id}, using 'now' or previously fake 'now'." if BufferManager.instantiated?
      @date = (@date || Time.now.to_time)
    end

    @to = Person.from_address_list (m.fetch_header (:to))
    @cc = Person.from_address_list (m.fetch_header (:cc))
    @bcc = Person.from_address_list (m.fetch_header (:bcc))

    @subj = (m.subject || DEFAULT_SUBJECT)
    @replyto = Person.from_address (m.fetch_header (:reply_to))

    ## before loading our full header from the source, we can actually
    ## have some extra refs set by the UI. (this happens when the user
    ## joins threads manually). so we will merge the current refs values
    ## in here.
    begin
      @refs += m.fetch_message_ids(:references)
      @replytos = m.fetch_message_ids(:in_reply_to)
    rescue Mail::Field::FieldError => e
      raise InvalidMessageError, e.message
    end
    @refs += @replytos unless @refs.member?(@replytos.first)
    @refs = @refs.uniq # user may have set some refs manually

    @recipient_email = (m.fetch_header(:Envelope_to) || m.fetch_header(:x_original_to) || m.fetch_header(:delivered_to))

    @list_subscribe = m.fetch_header(:list_subscribe)
    @list_unsubscribe = m.fetch_header(:list_unsubscribe)
    @list_address = Person.from_address(get_email_from_mailto(m.fetch_header(:list_post) || m.fetch_header(:x_mailing_list)))

    @source_marked_read = m.fetch_header(:status) == 'RO'
  end

  # get to field from mailto:example@example uri
  def get_email_from_mailto field
    return nil if field.nil?
    u = URI
    k = u.extract field, 'mailto'
    a = u.parse k[0]
    return a.to
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
  def is_draft?; @labels.member? :draft; end
  def draft_filename
    raise "not a draft" unless is_draft?
    source.fn_for_offset source_info
  end

  ## sanitize message ids by removing spaces and non-ascii characters.
  ## also, truncate to 255 characters. all these steps are necessary
  ## to make the index happy. of course, we probably fuck up a couple
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

  def location
    @locations.find { |x| x.valid? } || raise(OutOfSyncSourceError.new)
  end

  def source
    location.source
  end

  def source_info
    location.info
  end

  ## this is called when the message body needs to actually be loaded.
  def load_from_source!
    @chunks ||=
      begin
        ## we need to re-read the header because it contains information
        ## that we don't store in the index. actually i think it's just
        ## the mailing list address (if any), so this is kinda overkill.
        ## i could just store that in the index, but i think there might
        ## be other things like that in the future, and i'd rather not
        ## bloat the index.
        ## actually, it's also the differentiation between to/cc/bcc,
        ## so i will keep this.
        rmsg = location.parsed_message

        parse_header rmsg
        message_to_chunks rmsg
      rescue SourceError, SocketError, Mail::UnknownEncodingType => e
        warn "problem reading message #{id}"
        debug "could not load message: #{location.inspect}, exception: #{e.inspect}"

        [Chunk::Text.new(error_message.split("\n"))]

      rescue Exception => e

        warn "problem reading message #{id}"
        debug "could not load message: #{location.inspect}, exception: #{e.inspect}"

        raise e

      end
  end

  def reload_from_source!
    @chunks = nil
    load_from_source!
  end


  def error_message
    <<EOS
#@snippet...

***********************************************************************
 An error occurred while loading this message.
***********************************************************************
EOS
  end

  def raw_header
    location.raw_header
  end

  def raw_message
    location.raw_message
  end

  def each_raw_message_line &b
    location.each_raw_message_line &b
  end

  def sync_back
    @locations.map { |l| l.sync_back @labels, self }.any? do
      UpdateManager.relay self, :updated, self
    end
  end

  def merge_labels_from_locations merge_labels
    ## Get all labels from all locations
    location_labels = Set.new([])

    @locations.each do |l|
      if l.valid?
        location_labels = location_labels.union(l.labels?)
      end
    end

    ## Add to the message labels the intersection between all location
    ## labels and those we want to merge
    location_labels = location_labels.intersection(merge_labels.to_set)

    if not location_labels.empty?
      @labels = @labels.union(location_labels)
      @dirty = true
    end
  end

  ## returns all the content from a message that will be indexed
  def indexable_content
    load_from_source!
    [
      from && from.indexable_content,
      to.map { |p| p.indexable_content },
      cc.map { |p| p.indexable_content },
      bcc.map { |p| p.indexable_content },
      indexable_chunks.map { |c| c.lines.map { |l| l.fix_encoding! } },
      indexable_subject,
    ].flatten.compact.join " "
  end

  def indexable_body
    indexable_chunks.map { |c| c.lines.each { |l| l.fix_encoding!} }.flatten.compact.join " "
  end

  def indexable_chunks
    chunks.select { |c| c.indexable? } || []
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
    m = Message.new :locations => [Location.new(source, source_info)]
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
    if payload.content_type && payload.content_type.downcase == "application/pgp-signature"
      warn "multipart/signed with payload content type #{payload.content_type}"
      return
    end

    if signature.content_type && signature.content_type.downcase != "application/pgp-signature"
      ## unknown signature type; just ignore.
      #warn "multipart/signed with signature content type #{signature.content_type}"
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

    if payload.content_type && payload.content_type.downcase != "application/octet-stream"
      warn "multipart/encrypted with payload content type #{payload.content_type}"
      return
    end

    if control.content_type && control.content_type.downcase != "application/pgp-encrypted"
      warn "multipart/encrypted with control content type #{signature.content_type}"
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

  ## takes Mail and breaks it into Chunk::s
  def message_to_chunks m, encrypted=false, sibling_types=[]
    if encrypted
      info "Encrypted message not implemented, skipping."
      return []
      #raise NotImplementedError
    end

    preferred_type = "text/plain" # TODO: im just gonna assume this is preferred

    chunks = []

    mime_parts(m, preferred_type).each do |type, filename, id, content|
      if type == "message/rfc822"
        info "RFC822 messages not implemented, skipping."
        next
        #raise NotImplementedError
      elsif type == "application/pgp"
        info "Encrypted PGP message not implemented, skipping."
        next
        #raise NotImplementedError
      else
        ## if there is a filename, we'll treat it as an attachment
        if filename
          @attachments.push filename.downcase unless filename =~ /^sup-attachment-/
          add_label :attachment unless filename =~ /^sup-attachment-/

          chunks << Chunk::Attachment.new(type, filename, content, sibling_types)

        else
          body = content

          # check for inline PGP
          #ch = inline_gpg_to_chunks body, $encoding, 'UTF-8'
          #chunks << ch if ch

          text_to_chunks(body.normalize_whitespace.split("\n"), encrypted).each do |tc|
            chunks << tc
          end
        end
      end
    end

    chunks

  end

  def mime_parts m, preferred_type
    decode_mime_parts m, preferred_type
  end

  def mime_part_types part
    ptype = part.fetch_header(:content_type)
    [ptype] + (part.multipart? ? part.body.parts.map { |sub| mime_part_types sub } : [])
  end

  ## unnests all the mime stuff and returns a list of [type, filename, content]
  ## tuples.
  ##
  ## for multipart/alternative parts, will only return the subpart that matches
  ## preferred_type. if none of them, will only return the first subpart.
  def decode_mime_parts part, preferred_type, level=0
    if part.multipart?
      if mime_type_for(part) =~ /multipart\/alternative/
        target = part.body.parts.find { |p| mime_type_for(p).index(preferred_type) } || part.body.parts.first
        if target # this can be nil
          decode_mime_parts target, preferred_type, level + 1
        else
          []
        end
      else # decode 'em all
        part.body.parts.compact.map { |subpart| decode_mime_parts subpart, preferred_type, level + 1 }.flatten 1
      end
    else
      type = mime_type_for part
      filename = mime_filename_for part
      id = mime_id_for part
      content = mime_content_for part, preferred_type
      [[type, filename, id, content]]
    end
  end

  def mime_type_for part
    (part.fetch_header(:content_type) || "text/plain").gsub(/\s+/, " ").strip.downcase
  end

  def mime_id_for part
    header = part.fetch_header(:content_id)
    case header
      when /<(.+?)>/; $1
      else header
    end
  end

  ## a filename, or nil
  def mime_filename_for part
    cd = part.fetch_header(:content_disposition)
    ct = part.fetch_header(:content_type)

    ## RFC 2183 (Content-Disposition) specifies that disposition-parms are
    ## separated by ";". So, we match everything up to " and ; (if present).
    filename = if ct && ct =~ /name="?(.*?[^\\])("|;|\z)/im # find in content-type
      $1
    elsif cd && cd =~ /filename="?(.*?[^\\])("|;|\z)/m # find in content-disposition
      $1
    end
  end


  #CONVERSIONS = {
    #["text/html", "text/plain"] => :html_to_text
  #}

  def mime_content_for mime_part, preferred_type
    return "" unless mime_part.body # sometimes this happens. not sure why.

    content_type = mime_part.fetch_header(:content_type) || "text/plain"
    source_charset = mime_part.charset || "UTF-8"

    content = mime_part.decoded
    #converted_content, converted_charset = if(converter = CONVERSIONS[[content_type, preferred_type]])
      #send converter, content, source_charset
    #else
      #[content, source_charset]
    #end

    # decode
    #if content_type =~ /^text\//
      #Decoder.transcode "utf-8", converted_charset, converted_content
    #else
      #converted_content
    #end
    content
  end

  def has_attachment? m
    m.has_attachments?
  end

  ## takes a RMail::Message, breaks it into Chunk:: classes.
  #def _message_to_chunks m, encrypted=false, sibling_types=[]
    #if m.multipart?
      #chunks =
        #case m.content_type.downcase
        #when "multipart/signed"
          #multipart_signed_to_chunks m
        #when "multipart/encrypted"
          #multipart_encrypted_to_chunks m
        #end

      #unless chunks
        #sibling_types = m.body.map { |p| p.content_type }
        #chunks = m.body.map { |p| message_to_chunks p, encrypted, sibling_types }.flatten.compact
      #end

      #chunks
    #elsif m[:content_type] && m.fetch_header(:content_type).downcase == "message/rfc822"
      #encoding = m.header["Content-Transfer-Encoding"]
      #if m.body
        #body =
        #case encoding
        #when "base64"
          #m.body.unpack("m")[0]
        #when "quoted-printable"
          #m.body.unpack("M")[0]
        #when "7bit", "8bit", nil
          #m.body
        #else
          #raise RMail::EncodingUnsupportedError, encoding.inspect
        #end
        #body = body.normalize_whitespace
        #payload = RMail::Parser.read(body)
        #from = payload.header.from.first ? payload.header.from.first.format : ""
        #to = payload.header.to.map { |p| p.format }.join(", ")
        #cc = payload.header.cc.map { |p| p.format }.join(", ")
        #subj = decode_header_field(payload.header.subject) || DEFAULT_SUBJECT
        #subj = Message.normalize_subj(subj.gsub(/\s+/, " ").gsub(/\s+$/, ""))
        #msgdate = payload.header.date
        #from_person = from ? Person.from_address(decode_header_field(from)) : nil
        #to_people = to ? Person.from_address_list(decode_header_field(to)) : nil
        #cc_people = cc ? Person.from_address_list(decode_header_field(cc)) : nil
        #[Chunk::EnclosedMessage.new(from_person, to_people, cc_people, msgdate, subj)] + message_to_chunks(payload, encrypted)
      #else
        #debug "no body for message/rfc822 enclosure; skipping"
        #[]
      #end
    #elsif m[:content_type] && m.fetch_header(:content_type).downcase == "application/pgp" && m.body
      ### apparently some versions of Thunderbird generate encryped email that
      ### does not follow RFC3156, e.g. messages with X-Enigmail-Version: 0.95.0
      ### they have no MIME multipart and just set the body content type to
      ### application/pgp. this handles that.
      ###
      ### TODO: unduplicate code between here and multipart_encrypted_to_chunks
      #notice, sig, decryptedm = CryptoManager.decrypt m.body
      #if decryptedm # managed to decrypt
        #children = message_to_chunks decryptedm, true
        #[notice, sig].compact + children
      #else
        #[notice]
      #end
    #else
      #filename =
        ### first, paw through the headers looking for a filename.
        ### RFC 2183 (Content-Disposition) specifies that disposition-parms are
        ### separated by ";". So, we match everything up to " and ; (if present).
        #if m.header["Content-Disposition"] && m.header["Content-Disposition"] =~ /filename="?(.*?[^\\])("|;|\z)/m
          #$1
        #elsif m.header["Content-Type"] && m.header["Content-Type"] =~ /name="?(.*?[^\\])("|;|\z)/im
          #$1

        ### haven't found one, but it's a non-text message. fake
        ### it.
        ###
        ### TODO: make this less lame.
        #elsif m.header["Content-Type"] && m.header["Content-Type"] !~ /^text\/plain/i
          #extension =
            #case m.header["Content-Type"]
            #when /text\/html/ then "html"
            #when /image\/(.*)/ then $1
            #end

          #["sup-attachment-#{Time.now.to_i}-#{rand 10000}", extension].join(".")
        #end

      ### if there's a filename, we'll treat it as an attachment.
      #if filename
        ### filename could be 2047 encoded
        #filename = Rfc2047.decode_to $encoding, filename
        ## add this to the attachments list if its not a generated html
        ## attachment (should we allow images with generated names?).
        ## Lowercase the filename because searches are easier that way
        #@attachments.push filename.downcase unless filename =~ /^sup-attachment-/
        #add_label :attachment unless filename =~ /^sup-attachment-/
        #content_type = (m.content_type || "application/unknown").downcase # sometimes RubyMail gives us nil
        #[Chunk::Attachment.new(content_type, filename, m, sibling_types)]

      ### otherwise, it's body text
      #else
        ### Decode the body, charset conversion will follow either in
        ### inline_gpg_to_chunks (for inline GPG signed messages) or
        ### a few lines below (messages without inline GPG)
        #body = m.body ? m.decoded : ""

        ### Check for inline-PGP
        #chunks = inline_gpg_to_chunks body, $encoding, (m.charset || $encoding)
        #return chunks if chunks

        #if m.body
          ### if there's no charset, use the current encoding as the charset.
          ### this ensures that the body is normalized to avoid non-displayable
          ### characters
          ##body = Iconv.easy_decode($encoding, m.charset || $encoding, m.decoded)
          #body = m.body.decoded
        #else
          #body = ""
        #end

        #text_to_chunks(body.normalize_whitespace.split("\n"), encrypted)
      #end
    #end
  #end

  ## looks for gpg signed (but not encrypted) inline  messages inside the
  ## message body (there is no extra header for inline GPG) or for encrypted
  ## (and possible signed) inline GPG messages
  def inline_gpg_to_chunks body, encoding_to, encoding_from
    lines = body.split("\n")

    # First case: Message is enclosed between
    #
    # -----BEGIN PGP SIGNED MESSAGE-----
    # and
    # -----END PGP SIGNED MESSAGE-----
    #
    # In some cases, END PGP SIGNED MESSAGE doesn't appear
    # (and may leave strange -----BEGIN PGP SIGNATURE----- ?)
    gpg = lines.between(GPG_SIGNED_START, GPG_SIGNED_END)
    # between does not check if GPG_END actually exists
    # Reference: http://permalink.gmane.org/gmane.mail.sup.devel/641
    if !gpg.empty?
      msg = RMail::Message.new
      msg.body = gpg.join("\n")

      body = body.transcode(encoding_to, encoding_from)
      lines = body.split("\n")
      sig = lines.between(GPG_SIGNED_START, GPG_SIG_START)
      startidx = lines.index(GPG_SIGNED_START)
      endidx = lines.index(GPG_SIG_END)
      before = startidx != 0 ? lines[0 .. startidx-1] : []
      after = endidx ? lines[endidx+1 .. lines.size] : []

      # sig contains BEGIN PGP SIGNED MESSAGE and END PGP SIGNATURE, so
      # we ditch them. sig may also contain the hash used by PGP (with a
      # newline), so we also skip them
      sig_start = sig[1].match(/^Hash:/) ? 3 : 1
      sig_end = sig.size-2
      payload = RMail::Message.new
      payload.body = sig[sig_start, sig_end].join("\n")
      return [text_to_chunks(before, false),
              CryptoManager.verify(nil, msg, false),
              message_to_chunks(payload),
              text_to_chunks(after, false)].flatten.compact
    end

    # Second case: Message is encrypted

    gpg = lines.between(GPG_START, GPG_END)
    # between does not check if GPG_END actually exists
    if !gpg.empty? && !lines.index(GPG_END).nil?
      msg = RMail::Message.new
      msg.body = gpg.join("\n")

      startidx = lines.index(GPG_START)
      before = startidx != 0 ? lines[0 .. startidx-1] : []
      after = lines[lines.index(GPG_END)+1 .. lines.size]

      notice, sig, decryptedm = CryptoManager.decrypt msg, true
      chunks = if decryptedm # managed to decrypt
        children = message_to_chunks(decryptedm, true)
        [notice, sig].compact + children
      else
        [notice]
      end
      return [text_to_chunks(before, false),
              chunks,
              text_to_chunks(after, false)].flatten.compact
    end
  end

  ## parse the lines of text into chunk objects.  the heuristics here
  ## need tweaking in some nice manner. TODO: move these heuristics
  ## into the classes themselves.
  def text_to_chunks lines, encrypted
    state = :text # one of :text, :quote, or :sig
    chunks = []
    chunk_lines = []
    nextline_index = -1

    lines.each_with_index do |line, i|
      if i >= nextline_index
        # look for next nonblank line only when needed to avoid O(n²)
        # behavior on sequences of blank lines
        if nextline_index = lines[(i+1)..-1].index { |l| l !~ /^\s*$/ } # skip blank lines
          nextline_index += i + 1
          nextline = lines[nextline_index]
        else
          nextline_index = lines.length
          nextline = nil
        end
      end

      case state
      when :text
        newstate = nil

        ## the following /:$/ followed by /\w/ is an attempt to detect the
        ## start of a quote. this is split into two regexen because the
        ## original regex /\w.*:$/ had very poor behavior on long lines
        ## like ":a:a:a:a:a" that occurred in certain emails.
        if line =~ QUOTE_PATTERN || (line =~ /:$/ && line =~ /\w/ && nextline =~ QUOTE_PATTERN)
          newstate = :quote
        elsif line =~ SIG_PATTERN && (lines.length - i) < MAX_SIG_DISTANCE && !lines[(i+1)..-1].index { |l| l =~ /^-- $/ }
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
        oldlen = @snippet.length
        @snippet = @snippet[0 ... SNIPPET_LEN].chomp
        @snippet += "..." if @snippet.length < oldlen
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

class Location
  attr_reader :source
  attr_reader :info

  def initialize source, info
    @source = source
    @info = info
  end

  def raw_header
    source.raw_header info
  end

  def raw_message
    source.raw_message info
  end

  def sync_back labels, message
    synced = false
    return synced unless sync_back_enabled? and valid?
    source.synchronize do
      new_info = source.sync_back(@info, labels)
      if new_info
        @info = new_info
        Index.sync_message message, true
        synced = true
      end
    end
    synced
  end

  def sync_back_enabled?
    source.respond_to? :sync_back and $config[:sync_back_to_maildir] and source.sync_back_enabled?
  end

  ## much faster than raw_message
  def each_raw_message_line &b
    source.each_raw_message_line info, &b
  end

  def parsed_message
    source.load_message info
  end

  def valid?
    source.valid? info
  end

  def labels?
    source.labels? info
  end

  def == o
    o.source.id == source.id and o.info == info
  end

  def hash
    [source.id, info].hash
  end
end

end
