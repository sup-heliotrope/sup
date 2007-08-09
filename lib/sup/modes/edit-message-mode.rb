require 'tempfile'
require 'socket' # just for gethostname!
require 'pathname'
require 'rmail'

module Redwood

class SendmailCommandFailed < StandardError; end

class EditMessageMode < LineCursorMode
  FORCE_HEADERS = %w(From To Cc Bcc Subject)
  MULTI_HEADERS = %w(To Cc Bcc)
  NON_EDITABLE_HEADERS = %w(Message-Id Date)

  attr_reader :status
  attr_accessor :body, :header
  bool_reader :edited

  register_keymap do |k|
    k.add :send_message, "Send message", 'y'
    k.add :edit_field, "Edit field", 'e'
    k.add :edit_message, "Edit message", :enter
    k.add :save_as_draft, "Save as draft", 'P'
    k.add :attach_file, "Attach a file", 'a'
    k.add :delete_attachment, "Delete an attachment", 'd'
  end

  def initialize opts={}
    @header = opts.delete(:header) || {} 
    @header_lines = []

    @body = opts.delete(:body) || []
    @body += sig_lines if $config[:edit_signature]

    @attachments = []
    @message_id = "<#{Time.now.to_i}-sup-#{rand 10000}@#{Socket.gethostname}>"
    @edited = false
    @skip_top_rows = opts[:skip_top_rows] || 0

    super opts
    regen_text
  end

  def lines; @text.length end
  def [] i; @text[i] end

  ## a hook
  def handle_new_text header, body; end

  def edit_field
    if (curpos - @skip_top_rows) >= @header_lines.length
      edit_message
    else
      case(field = @header_lines[curpos - @skip_top_rows])
      when "Subject"
        text = BufferManager.ask :subject, "Subject: ", @header[field]
        @header[field] = parse_header field, text if text
      else
        default =
          case field
          when *MULTI_HEADERS
            @header[field].join(", ")
          else
            @header[field]
          end

        contacts = BufferManager.ask_for_contacts :people, "#{field}: ", default
        if contacts
          text = contacts.map { |s| s.longname }.join(", ")
          @header[field] = parse_header field, text
        end
      end
      update
    end
  end

  def edit_message
    @file = Tempfile.new "sup.#{self.class.name.gsub(/.*::/, '').camel_to_hyphy}"
    @file.puts format_headers(@header - NON_EDITABLE_HEADERS).first
    @file.puts
    @file.puts @body
    @file.close

    editor = $config[:editor] || ENV['EDITOR'] || "/usr/bin/vi"

    mtime = File.mtime @file.path
    BufferManager.shell_out "#{editor} #{@file.path}"
    @edited = true if File.mtime(@file.path) > mtime

    BufferManager.kill_buffer self.buffer unless @edited

    header, @body = parse_file @file.path
    @header = header - NON_EDITABLE_HEADERS
    handle_new_text @header, @body
    update
  end

  def killable?
    !edited? || BufferManager.ask_yes_or_no("Discard message?")
  end

  def attach_file
    fn = BufferManager.ask_for_filenames :attachment, "File name (enter for browser): "
    fn.each { |f| @attachments << Pathname.new(f) }
    update
  end

  def delete_attachment
    i = (curpos - @skip_top_rows) - @attachment_lines_offset
    if i >= 0 && i < @attachments.size && BufferManager.ask_yes_or_no("Delete attachment #{@attachments[i]}?")
      @attachments.delete_at i
      update
    end
  end

protected

  def update
    regen_text
    buffer.mark_dirty if buffer
  end

  def regen_text
    header, @header_lines = format_headers(@header - NON_EDITABLE_HEADERS) + [""]
    @text = header + [""] + @body
    @text += sig_lines unless $config[:edit_signature]

    unless @attachments.empty?
      @text += [""]
      @attachment_lines_offset = @text.length
      @text += @attachments.map { |f| [[:attachment_color, "+ Attachment: #{f} (#{f.human_size})"]] }
    end
  end

  def parse_file fn
    File.open(fn) do |f|
      header = MBox::read_header f
      body = f.readlines

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
            (" " * (header.length + 1)) + name
          end + (i == things.length - 1 ? "" : ",")
        end
      end
    end
  end

  def send_message
    return unless edited? || BufferManager.ask_yes_or_no("Message unedited. Really send?")

    date = Time.now
    from_email = 
      if @header["From"] =~ /<?(\S+@(\S+?))>?$/
        $1
      else
        AccountManager.default_account.email
      end

    acct = AccountManager.account_for(from_email) || AccountManager.default_account
    BufferManager.flash "Sending..."

    begin
      IO.popen(acct.sendmail, "w") { |p| write_full_message_to p, date }
      raise SendmailCommandFailed, "Couldn't execute #{acct.sendmail}" unless $? == 0
      SentManager.write_sent_message(date, from_email) { |f| write_full_message_to f, date }
      BufferManager.kill_buffer buffer
      BufferManager.flash "Message sent!"
    rescue SystemCallError, SendmailCommandFailed => e
      Redwood::log "Problem sending mail: #{e.message}"
      BufferManager.flash "Problem sending mail: #{e.message}"
    end
  end

  def save_as_draft
    DraftManager.write_draft { |f| write_message f, false }
    BufferManager.kill_buffer buffer
    BufferManager.flash "Saved for later editing."
  end

  def write_full_message_to f, date=Time.now
    m = RMail::Message.new
    @header.each do |k, v|
      next if v.nil? || v.empty?
      m.header[k] = 
        case v
        when String
          v
        when Array
          v.join ", "
        end
    end

    m.header["Date"] = date.rfc2822
    m.header["Message-Id"] = @message_id
    m.header["User-Agent"] = "Sup/#{Redwood::VERSION}"

    if @attachments.empty?
      m.header["Content-Disposition"] = "inline"
      m.header["Content-Type"] = "text/plain; charset=#{$encoding}"
      m.body = @body.join
      m.body += sig_lines.join("\n") unless $config[:edit_signature]
    else
      body_m = RMail::Message.new
      body_m.body = @body.join
      body_m.body += sig_lines.join("\n") unless $config[:edit_signature]
      
      m.add_part body_m
      @attachments.each { |fn| m.add_attachment fn.to_s }
    end
    f.puts m.to_s
  end

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
    f.puts @body.map { |l| l =~ /^From / ? ">#{l}" : l }
    f.puts sig_lines if full unless $config[:edit_signature]
  end  

private

  def sig_lines
    p = PersonManager.person_for @header["From"]
    sigfn = (AccountManager.account_for(p.email) || 
             AccountManager.default_account).signature

    if sigfn && File.exists?(sigfn)
      ["", "-- "] + File.readlines(sigfn).map { |l| l.chomp }
    else
      []
    end
  end
end

end
