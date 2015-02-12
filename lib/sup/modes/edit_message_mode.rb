require 'tempfile'
require 'socket' # just for gethostname!
require 'pathname'

module Redwood

class SendmailCommandFailed < StandardError; end

class EditMessageMode < LineCursorMode
  DECORATION_LINES = 1

  FORCE_HEADERS = %w(From To Cc Bcc Subject)
  MULTI_HEADERS = %w(To Cc Bcc)
  NON_EDITABLE_HEADERS = %w(Message-id Date)

  HookManager.register "signature", <<EOS
Generates a message signature.
Variables:
      header: an object that supports string-to-string hashtable-style access
              to the raw headers for the message. E.g., header["From"],
              header["To"], etc.
  from_email: the email part of the From: line, or nil if empty
  message_id: the unique message id of the message
Return value:
  A string (multi-line ok) containing the text of the signature, or nil to
  use the default signature, or :none for no signature.
EOS

  HookManager.register "check-attachment", <<EOS
Do checks on the attachment filename
Variables:
	filename: the name of the attachment
Return value:
    A String (single line) containing a message why this attachment is not optimal
    to be attached.
    If it is ok just return an empty string or nil
EOS

  HookManager.register "before-edit", <<EOS
Modifies message body and headers before editing a new message. Variables
should be modified in place.
Variables:
	header: a hash of headers. See 'signature' hook for documentation.
	body: an array of lines of body text.
Return value:
	none
EOS

  HookManager.register "mentions-attachments", <<EOS
Detects if given message mentions attachments the way it is probable
that there should be files attached to the message.
Variables:
	header: a hash of headers. See 'signature' hook for documentation.
	body: an array of lines of body text.
Return value:
	True if attachments are mentioned.
EOS

  HookManager.register "crypto-mode", <<EOS
Modifies cryptography settings based on header and message content, before
editing a new message. This can be used to set, for example, default cryptography
settings.
Variables:
    header: a hash of headers. See 'signature' hook for documentation.
    body: an array of lines of body text.
    crypto_selector: the UI element that controls the current cryptography setting.
Return value:
     none
EOS

  HookManager.register "sendmail", <<EOS
Sends the given mail. If this hook doesn't exist, the sendmail command
configured for the account is used.
The message will be saved after this hook is run, so any modification to it
will be recorded.
Variables:
    message: RMail::Message instance of the mail to send
    account: Account instance matching the From address
Return value:
     True if mail has been sent successfully, false otherwise.
EOS

  attr_reader :status
  attr_accessor :body, :header
  bool_reader :edited

  register_keymap do |k|
    k.add :send_message, "Send message", 'y'
    k.add :edit_message_or_field, "Edit selected field", 'e'
    k.add :edit_to, "Edit To:", 't'
    k.add :edit_cc, "Edit Cc:", 'c'
    k.add :edit_subject, "Edit Subject", 's'
    k.add :default_edit_message, "Edit message (default)", :enter
    k.add :alternate_edit_message, "Edit message (alternate, asynchronously)", 'E'
    k.add :save_as_draft, "Save as draft", 'P'
    k.add :attach_file, "Attach a file", 'a'
    k.add :delete_attachment, "Delete an attachment", 'd'
    k.add :move_cursor_right, "Move selector to the right", :right, 'l'
    k.add :move_cursor_left, "Move selector to the left", :left, 'h'
  end

  def initialize opts={}
    @header = opts.delete(:header) || {}
    @header_lines = []

    @body = opts.delete(:body) || []

    if opts[:attachments]
      @attachments = opts[:attachments].values
      @attachment_names = opts[:attachments].keys
    else
      @attachments = []
      @attachment_names = []
    end

    begin
      hostname = File.open("/etc/mailname", "r").gets.chomp
    rescue
      nil
    end
    hostname = Socket.gethostname if hostname.nil? or hostname.empty?

    @message_id = "<#{Time.now.to_i}-sup-#{rand 10000}@#{hostname}>"
    @edited = false
    @sig_edited = false
    @selectors = []
    @selector_label_width = 0
    @async_mode = nil

    HookManager.run "before-edit", :header => @header, :body => @body

    @account_selector = nil
    # only show account selector if there is more than one email address
    if $config[:account_selector] && AccountManager.user_emails.length > 1
      ## Duplicate e-mail strings to prevent a "can't modify frozen
      ## object" crash triggered by the String::display_length()
      ## method in util.rb
      user_emails_copy = []
      AccountManager.user_emails.each { |e| user_emails_copy.push e.dup }

      @account_selector =
        HorizontalSelector.new "Account:", AccountManager.user_emails + [nil], user_emails_copy + ["Customized"]

      if @header["From"] =~ /<?(\S+@(\S+?))>?$/
        # TODO: this is ugly. might implement an AccountSelector and handle
        # special cases more transparently.
        account_from = @account_selector.can_set_to?($1) ? $1 : nil
        @account_selector.set_to account_from
      else
        @account_selector.set_to nil
      end

      # A single source of truth might better than duplicating this in both
      # @account_user and @account_selector.
      @account_user = @header["From"]

      add_selector @account_selector
    end

    @crypto_selector =
      if CryptoManager.have_crypto?
        HorizontalSelector.new "Crypto:", [:none] + CryptoManager::OUTGOING_MESSAGE_OPERATIONS.keys, ["None"] + CryptoManager::OUTGOING_MESSAGE_OPERATIONS.values
      end
    add_selector @crypto_selector if @crypto_selector

    if @crypto_selector
      HookManager.run "crypto-mode", :header => @header, :body => @body, :crypto_selector => @crypto_selector
    end

    super opts
    regen_text
  end

  def lines; @text.length + (@selectors.empty? ? 0 : (@selectors.length + DECORATION_LINES)) end

  def [] i
    if @selectors.empty?
      @text[i]
    elsif i < @selectors.length
      @selectors[i].line @selector_label_width
    elsif i == @selectors.length
      ""
    else
      @text[i - @selectors.length - DECORATION_LINES]
    end
  end

  ## hook for subclasses. i hate this style of programming.
  def handle_new_text header, body; end

  def edit_message_or_field
    lines = (@selectors.empty? ? 0 : DECORATION_LINES) + @selectors.size
    if lines > curpos
      return
    elsif (curpos - lines) >= @header_lines.length
      default_edit_message
    else
      edit_field @header_lines[curpos - lines]
    end
  end

  def edit_to; edit_field "To" end
  def edit_cc; edit_field "Cc" end
  def edit_subject; edit_field "Subject" end

  def save_message_to_file
    sig = sig_lines.join("\n")
    @file = Tempfile.new ["sup.#{self.class.name.gsub(/.*::/, '').camel_to_hyphy}", ".eml"]
    @file.puts format_headers(@header - NON_EDITABLE_HEADERS).first
    @file.puts

    begin
      text = @body.join("\n")
    rescue Encoding::CompatibilityError
      text = @body.map { |x| x.fix_encoding! }.join("\n")
      debug "encoding problem while writing message, trying to rescue, but expect errors: #{text}"
    end

    @file.puts text
    @file.puts sig if ($config[:edit_signature] and !@sig_edited)
    @file.close
  end

  def set_sig_edit_flag
    sig = sig_lines.join("\n")
    if $config[:edit_signature]
      pbody = @body.map { |x| x.fix_encoding! }.join("\n").fix_encoding!
      blen = pbody.length
      slen = sig.length

      if blen > slen and pbody[blen-slen..blen] == sig
        @sig_edited = false
        @body = pbody[0..blen-slen].fix_encoding!.split("\n")
      else
        @sig_edited = true
      end
    end
  end

  def default_edit_message
    if $config[:always_edit_async]
      return edit_message_async
    else
      return edit_message
    end
  end

  def alternate_edit_message
    if $config[:always_edit_async]
      return edit_message
    else
      return edit_message_async
    end
  end

  def edit_message
    old_from = @header["From"] if @account_selector

    begin
      save_message_to_file
    rescue SystemCallError => e
      BufferManager.flash "Can't save message to file: #{e.message}"
      return
    end

    editor = $config[:editor] || ENV['EDITOR'] || "/usr/bin/vi"

    mtime = File.mtime @file.path
    BufferManager.shell_out "#{editor} #{@file.path}"
    @edited = true if File.mtime(@file.path) > mtime

    return @edited unless @edited

    header, @body = parse_file @file.path
    @header = header - NON_EDITABLE_HEADERS
    set_sig_edit_flag

    if @account_selector and @header["From"] != old_from
      @account_user = @header["From"]
      @account_selector.set_to nil
    end

    handle_new_text @header, @body
    rerun_crypto_selector_hook
    update

    @edited
  end

  def edit_message_async
    begin
      save_message_to_file
    rescue SystemCallError => e
      BufferManager.flash "Can't save message to file: #{e.message}"
      return
    end

    @mtime = File.mtime @file.path

    # put up buffer saying you can now edit the message in another
    # terminal or app, and continue to use sup in the meantime.
    subject = @header["Subject"] || ""
    @async_mode = EditMessageAsyncMode.new self, @file.path, subject
    BufferManager.spawn "Waiting for message \"#{subject}\" to be finished", @async_mode

    # hide ourselves, and wait for signal to resume from async mode ...
    buffer.hidden = true
  end

  def edit_message_async_resume being_killed=false
    buffer.hidden = false
    @async_mode = nil
    BufferManager.raise_to_front buffer if !being_killed

    @edited = true if File.mtime(@file.path) > @mtime

    header, @body = parse_file @file.path
    @header = header - NON_EDITABLE_HEADERS
    set_sig_edit_flag
    handle_new_text @header, @body
    update

    true
  end

  def killable?
    if !@async_mode.nil?
      return false if !@async_mode.killable?
      if File.mtime(@file.path) > @mtime
        @edited = true
        header, @body = parse_file @file.path
        @header = header - NON_EDITABLE_HEADERS
        handle_new_text @header, @body
        update
      end
    end
    !edited? || BufferManager.ask_yes_or_no("Discard message?")
  end

  def unsaved?; edited? end

  def attach_file
    fn = BufferManager.ask_for_filename :attachment, "File name (enter for browser): "
    return unless fn
    if HookManager.enabled? "check-attachment"
        reason = HookManager.run("check-attachment", :filename => fn)
        if reason
            return unless BufferManager.ask_yes_or_no("#{reason} Attach anyway?")
        end
    end
    begin
      Dir[fn].each do |f|
        @attachments << RMail::Message.make_file_attachment(f)
        @attachment_names << f
      end
      update
    rescue SystemCallError => e
      BufferManager.flash "Can't read #{fn}: #{e.message}"
    end
  end

  def delete_attachment
    i = curpos - @attachment_lines_offset - (@selectors.empty? ? 0 : DECORATION_LINES) - @selectors.size
    if i >= 0 && i < @attachments.size && BufferManager.ask_yes_or_no("Delete attachment #{@attachment_names[i]}?")
      @attachments.delete_at i
      @attachment_names.delete_at i
      update
    end
  end

protected

  def rerun_crypto_selector_hook
    if @crypto_selector && !@crypto_selector.changed_by_user
      HookManager.run "crypto-mode", :header => @header, :body => @body, :crypto_selector => @crypto_selector
    end
  end

  def mime_encode string
    string = [string].pack('M') # basic quoted-printable
    string.gsub!(/=\n/,'')      # .. remove trailing newline
    string.gsub!(/_/,'=5F')     # .. encode underscores
    string.gsub!(/\?/,'=3F')    # .. encode question marks
    string.gsub!(/ /,'_')       # .. translate space to underscores
    "=?utf-8?q?#{string}?="
  end

  def mime_encode_subject string
    return string if string.ascii_only?
    mime_encode string
  end

  RE_ADDRESS = /(.+)( <.*@.*>)/

  # Encode "bælammet mitt <user@example.com>" into
  # "=?utf-8?q?b=C3=A6lammet_mitt?= <user@example.com>
  def mime_encode_address string
    return string if string.ascii_only?
    string.sub(RE_ADDRESS) { |match| mime_encode($1) + $2 }
  end

  def move_cursor_left
    if curpos < @selectors.length
      @selectors[curpos].roll_left
      buffer.mark_dirty
      update if @account_selector
    else
      col_left
    end
  end

  def move_cursor_right
    if curpos < @selectors.length
      @selectors[curpos].roll_right
      buffer.mark_dirty
      update if @account_selector
    else
      col_right
    end
  end

  def add_selector s
    @selectors << s
    @selector_label_width = [@selector_label_width, s.label.length].max
  end

  def update
    if @account_selector
      if @account_selector.val.nil?
        @header["From"] = @account_user
      else
        @header["From"] = AccountManager.full_address_for @account_selector.val
      end
    end

    regen_text
    buffer.mark_dirty if buffer
  end

  def regen_text
    header, @header_lines = format_headers(@header - NON_EDITABLE_HEADERS) + [""]
    @text = header + [""] + @body
    @text += sig_lines unless @sig_edited

    @attachment_lines_offset = 0

    unless @attachments.empty?
      @text += [""]
      @attachment_lines_offset = @text.length
      @text += (0 ... @attachments.size).map { |i| [[:attachment_color, "+ Attachment: #{@attachment_names[i]} (#{@attachments[i].body.size.to_human_size})"]] }
    end
  end

  def parse_file fn
    File.open(fn) do |f|
      header = Source.parse_raw_email_header(f).inject({}) { |h, (k, v)| h[k.capitalize] = v; h } # lousy HACK
      body = f.readlines.map { |l| l.chomp }

      header.delete_if { |k, v| NON_EDITABLE_HEADERS.member? k }
      header.each { |k, v| header[k] = parse_header k, v }

      [header, body]
    end
  end

  def parse_header k, v
    if MULTI_HEADERS.include?(k)
      v.split_on_commas.map do |name|
        (p = ContactManager.contact_for(name)) && p.full_address || name
      end
    else
      v
    end
  end

  def format_headers header
    header_lines = []
    headers = (FORCE_HEADERS + (header.keys - FORCE_HEADERS)).map do |h|
      lines = make_lines "#{h}:", header[h]
      lines.length.times { header_lines << h }
      lines
    end.flatten.compact
    [headers, header_lines]
  end

  def make_lines header, things
    case things
    when nil, []
      [header + " "]
    when String
      [header + " " + things]
    else
      if things.empty?
        [header]
      else
        things.map_with_index do |name, i|
          raise "an array: #{name.inspect} (things #{things.inspect})" if Array === name
          if i == 0
            header + " " + name
          else
            (" " * (header.display_length + 1)) + name
          end + (i == things.length - 1 ? "" : ",")
        end
      end
    end
  end

  def send_message
    return false if !edited? && !BufferManager.ask_yes_or_no("Message unedited. Really send?")
    return false if $config[:confirm_no_attachments] && mentions_attachments? && @attachments.size == 0 && !BufferManager.ask_yes_or_no("You haven't added any attachments. Really send?")#" stupid ruby-mode
    return false if $config[:confirm_top_posting] && top_posting? && !BufferManager.ask_yes_or_no("You're top-posting. That makes you a bad person. Really send?") #" stupid ruby-mode

    from_email =
      if @header["From"] =~ /<?(\S+@(\S+?))>?$/
        $1
      else
        AccountManager.default_account.email
      end

    acct = AccountManager.account_for(from_email) || AccountManager.default_account
    BufferManager.flash "Sending..."

    begin
      date = Time.now
      m = build_message date

      if HookManager.enabled? "sendmail"
        if not HookManager.run "sendmail", :message => m, :account => acct
              warn "Sendmail hook was not successful"
              return false
        end
      else
        IO.popen(acct.sendmail, "w:UTF-8") { |p| p.puts m }
        raise SendmailCommandFailed, "Couldn't execute #{acct.sendmail}" unless $? == 0
      end

      SentManager.write_sent_message(date, from_email) { |f| f.puts sanitize_body(m.to_s) }
      BufferManager.kill_buffer buffer
      BufferManager.flash "Message sent!"
      true
    rescue SystemCallError, SendmailCommandFailed, CryptoManager::Error => e
      warn "Problem sending mail: #{e.message}"
      BufferManager.flash "Problem sending mail: #{e.message}"
      false
    end
  end

  def save_as_draft
    DraftManager.write_draft { |f| write_message f, false }
    BufferManager.kill_buffer buffer
    BufferManager.flash "Saved for later editing."
  end

  def build_message date
    m = RMail::Message.new
    m.header["Content-Type"] = "text/plain; charset=#{$encoding}"
    m.body = @body.join("\n")
    m.body += "\n" + sig_lines.join("\n") unless @sig_edited
    ## body must end in a newline or GPG signatures will be WRONG!
    m.body += "\n" unless m.body =~ /\n\Z/
    m.body = m.body.fix_encoding!

    ## there are attachments, so wrap body in an attachment of its own
    unless @attachments.empty?
      body_m = m
      body_m.header["Content-Disposition"] = "inline"
      m = RMail::Message.new

      m.add_part body_m
      @attachments.each do |a|
        a.body = a.body.fix_encoding! if a.body.kind_of? String
        m.add_part a
      end
    end

    ## do whatever crypto transformation is necessary
    if @crypto_selector && @crypto_selector.val != :none
      from_email = Person.from_address(@header["From"]).email
      to_email = [@header["To"], @header["Cc"], @header["Bcc"]].flatten.compact.map { |p| Person.from_address(p).email }
      if m.multipart?
        m.each_part {|p| p = transfer_encode p}
      else
        m = transfer_encode m
      end

      m = CryptoManager.send @crypto_selector.val, from_email, to_email, m
    end

    ## finally, set the top-level headers
    @header.each do |k, v|
      next if v.nil? || v.empty?
      m.header[k] =
        case v
        when String
          (k.match(/subject/i) ? mime_encode_subject(v).dup.fix_encoding! : mime_encode_address(v)).dup.fix_encoding!
        when Array
          (v.map { |v| mime_encode_address v }.join ", ").dup.fix_encoding!
        end
    end

    m.header["Date"] = date.rfc2822
    m.header["Message-Id"] = @message_id
    m.header["User-Agent"] = "Sup/#{Redwood::VERSION}"
    m.header["Content-Transfer-Encoding"] ||= '8bit'
    m.header["MIME-Version"] = "1.0" if m.multipart?
    m
  end

  ## TODO: remove this. redundant with write_full_message_to.
  ##
  ## this is going to change soon: draft messages (currently written
  ## with full=false) will be output as yaml.
  def write_message f, full=true, date=Time.now
    raise ArgumentError, "no pre-defined date: header allowed" if @header["Date"]
    f.puts format_headers(@header).first
    f.puts <<EOS
Date: #{date.rfc2822}
Message-Id: #{@message_id}
EOS
    if full
      f.puts <<EOS
Mime-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline
User-Agent: Redwood/#{Redwood::VERSION}
EOS
    end

    f.puts
    f.puts sanitize_body(@body.join("\n"))
    f.puts sig_lines if full unless $config[:edit_signature]
  end

protected

  def edit_field field
    case field
    when "Subject"
      text = BufferManager.ask :subject, "Subject: ", @header[field]
       if text
         @header[field] = parse_header field, text
         update
       end
    else
      default = case field
        when *MULTI_HEADERS
          @header[field] ||= []
          @header[field].join(", ")
        else
          @header[field]
        end

      contacts = BufferManager.ask_for_contacts :people, "#{field}: ", default
      if contacts
        text = contacts.map { |s| s.full_address }.join(", ")
        @header[field] = parse_header field, text

        if @account_selector and field == "From"
          @account_user = @header["From"]
          @account_selector.set_to nil
        end

        rerun_crypto_selector_hook
        update
      end
    end
  end

private

  def sanitize_body body
    body.gsub(/^From /, ">From ")
  end

  def mentions_attachments?
    if HookManager.enabled? "mentions-attachments"
      HookManager.run "mentions-attachments", :header => @header, :body => @body
    else
      @body.any? {  |l| l.fix_encoding! =~ /^[^>]/ && l.fix_encoding! =~ /\battach(ment|ed|ing|)\b/i }
    end
  end

  def top_posting?
    @body.map { |x| x.fix_encoding! }.join("\n").fix_encoding! =~ /(\S+)\s*Excerpts from.*\n(>.*\n)+\s*\Z/
  end

  def sig_lines
    p = Person.from_address(@header["From"])
    from_email = p && p.email

    ## first run the hook
    hook_sig = HookManager.run "signature", :header => @header, :from_email => from_email, :message_id => @message_id

    return [] if hook_sig == :none
    return ["", "-- "] + hook_sig.split("\n") if hook_sig

    ## no hook, do default signature generation based on config.yaml
    return [] unless from_email
    sigfn = (AccountManager.account_for(from_email) ||
             AccountManager.default_account).signature

    if sigfn && File.exist?(sigfn)
      ["", "-- "] + File.readlines(sigfn).map { |l| l.chomp }
    else
      []
    end
  end

  def transfer_encode msg_part
    ## return the message unchanged if it's already encoded
    if (msg_part.header["Content-Transfer-Encoding"] == "base64" ||
        msg_part.header["Content-Transfer-Encoding"] == "quoted-printable")
      return msg_part
    end

    ## encode to quoted-printable for all text/* MIME types,
    ## use base64 otherwise
    if msg_part.header["Content-Type"] =~ /text\/.*/
      msg_part.header["Content-Transfer-Encoding"] = 'quoted-printable'
      msg_part.body = [msg_part.body].pack('M')
    else
      msg_part.header["Content-Transfer-Encoding"] = 'base64'
      msg_part.body = [msg_part.body].pack('m')
    end
    msg_part
  end
end

end
