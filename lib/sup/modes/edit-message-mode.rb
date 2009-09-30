require 'tempfile'
require 'socket' # just for gethostname!
require 'pathname'
require 'rmail'

# from jcode.rb, not included in ruby 1.9
PATTERN_UTF8 = '[\xc0-\xdf][\x80-\xbf]|[\xe0-\xef][\x80-\xbf][\x80-\xbf]'
RE_UTF8 = Regexp.new(PATTERN_UTF8, 0, 'n')

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
Return value:
  A string (multi-line ok) containing the text of the signature, or nil to
  use the default signature, or :none for no signature.
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

  attr_reader :status
  attr_accessor :body, :header
  bool_reader :edited

  register_keymap do |k|
    k.add :send_message, "Send message", 'y'
    k.add :edit_message_or_field, "Edit selected field", 'e'
    k.add :edit_to, "Edit To:", 't'
    k.add :edit_cc, "Edit Cc:", 'c'
    k.add :edit_subject, "Edit Subject", 's'
    k.add :edit_message, "Edit message", :enter
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
    @body += sig_lines if $config[:edit_signature] && !opts.delete(:have_signature)

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
    @selectors = []
    @selector_label_width = 0

    @crypto_selector =
      if CryptoManager.have_crypto?
        HorizontalSelector.new "Crypto:", [:none] + CryptoManager::OUTGOING_MESSAGE_OPERATIONS.keys, ["None"] + CryptoManager::OUTGOING_MESSAGE_OPERATIONS.values
      end
    add_selector @crypto_selector if @crypto_selector
    
    HookManager.run "before-edit", :header => @header, :body => @body

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
    lines = DECORATION_LINES + @selectors.size
    if lines > curpos
      return
    elsif (curpos - lines) >= @header_lines.length
      edit_message
    else
      edit_field @header_lines[curpos - lines]
    end
  end

  def edit_to; edit_field "To" end
  def edit_cc; edit_field "Cc" end
  def edit_subject; edit_field "Subject" end

  def edit_message
    @file = Tempfile.new "sup.#{self.class.name.gsub(/.*::/, '').camel_to_hyphy}"
    @file.puts format_headers(@header - NON_EDITABLE_HEADERS).first
    @file.puts
    @file.puts @body.join("\n")
    @file.close

    editor = $config[:editor] || ENV['EDITOR'] || "/usr/bin/vi"

    mtime = File.mtime @file.path
    BufferManager.shell_out "#{editor} #{@file.path}"
    @edited = true if File.mtime(@file.path) > mtime

    return @edited unless @edited

    header, @body = parse_file @file.path
    @header = header - NON_EDITABLE_HEADERS
    handle_new_text @header, @body
    update

    @edited
  end

  def killable?
    !edited? || BufferManager.ask_yes_or_no("Discard message?")
  end

  def unsaved?; edited? end

  def attach_file
    fn = BufferManager.ask_for_filename :attachment, "File name (enter for browser): "
    return unless fn
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
    i = curpos - @attachment_lines_offset - DECORATION_LINES - 1
    if i >= 0 && i < @attachments.size && BufferManager.ask_yes_or_no("Delete attachment #{@attachment_names[i]}?")
      @attachments.delete_at i
      @attachment_names.delete_at i
      update
    end
  end

protected

  def mime_encode string
    string = [string].pack('M') # basic quoted-printable
    string.gsub!(/=\n/,'')      # .. remove trailing newline
    string.gsub!(/_/,'=96')     # .. encode underscores
    string.gsub!(/\?/,'=3F')    # .. encode question marks
    string.gsub!(/ /,'_')       # .. translate space to underscores
    "=?utf-8?q?#{string}?="
  end

  def mime_encode_subject string
    return string unless string.match(RE_UTF8)
    mime_encode string
  end

  RE_ADDRESS = /(.+)( <.*@.*>)/

  # Encode "bælammet mitt <user@example.com>" into
  # "=?utf-8?q?b=C3=A6lammet_mitt?= <user@example.com>
  def mime_encode_address string
    return string unless string.match(RE_UTF8)
    string.sub(RE_ADDRESS) { |match| mime_encode($1) + $2 }
  end

  def move_cursor_left
    if curpos < @selectors.length
      @selectors[curpos].roll_left
      buffer.mark_dirty
    else
      col_left
    end
  end

  def move_cursor_right
    if curpos < @selectors.length
      @selectors[curpos].roll_right
      buffer.mark_dirty
    else
      col_right
    end
  end

  def add_selector s
    @selectors << s
    @selector_label_width = [@selector_label_width, s.label.length].max
  end

  def update
    regen_text
    buffer.mark_dirty if buffer
  end

  def regen_text
    header, @header_lines = format_headers(@header - NON_EDITABLE_HEADERS) + [""]
    @text = header + [""] + @body
    @text += sig_lines unless $config[:edit_signature]
    
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
      IO.popen(acct.sendmail, "w") { |p| p.puts m }
      raise SendmailCommandFailed, "Couldn't execute #{acct.sendmail}" unless $? == 0
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
    m.body += sig_lines.join("\n") unless $config[:edit_signature]
    ## body must end in a newline or GPG signatures will be WRONG!
    m.body += "\n" unless m.body =~ /\n\Z/

    ## there are attachments, so wrap body in an attachment of its own
    unless @attachments.empty?
      body_m = m
      body_m.header["Content-Disposition"] = "inline"
      m = RMail::Message.new
      
      m.add_part body_m
      @attachments.each { |a| m.add_part a }
    end

    ## do whatever crypto transformation is necessary
    if @crypto_selector && @crypto_selector.val != :none
      from_email = Person.from_address(@header["From"]).email
      to_email = [@header["To"], @header["Cc"], @header["Bcc"]].flatten.compact.map { |p| Person.from_address(p).email }

      m = CryptoManager.send @crypto_selector.val, from_email, to_email, m
    end

    ## finally, set the top-level headers
    @header.each do |k, v|
      next if v.nil? || v.empty?
      m.header[k] = 
        case v
        when String
          k.match(/subject/i) ? mime_encode_subject(v) : mime_encode_address(v)
        when Array
          v.map { |v| mime_encode_address v }.join ", "
        end
    end

    m.header["Date"] = date.rfc2822
    m.header["Message-Id"] = @message_id
    m.header["User-Agent"] = "Sup/#{Redwood::VERSION}"
    m.header["Content-Transfer-Encoding"] = '8bit'
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
        update
      end
    end
  end

private

  def sanitize_body body
    body.gsub(/^From /, ">From ")
  end

  def mentions_attachments?
    @body.any? { |l| l =~ /^[^>]/ && l =~ /\battach(ment|ed|ing|)\b/i }
  end

  def top_posting?
    @body.join("\n") =~ /(\S+)\s*Excerpts from.*\n(>.*\n)+\s*\Z/
  end

  def sig_lines
    p = Person.from_address(@header["From"])
    from_email = p && p.email

    ## first run the hook
    hook_sig = HookManager.run "signature", :header => @header, :from_email => from_email

    return [] if hook_sig == :none
    return ["", "-- "] + hook_sig.split("\n") if hook_sig

    ## no hook, do default signature generation based on config.yaml
    return [] unless from_email
    sigfn = (AccountManager.account_for(from_email) || 
             AccountManager.default_account).signature

    if sigfn && File.exists?(sigfn)
      ["", "-- "] + File.readlines(sigfn).map { |l| l.chomp }
    else
      []
    end
  end
end

end
