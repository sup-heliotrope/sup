require 'tempfile'
require 'socket' # just for gethostname!

module Redwood

class EditMessageMode < LineCursorMode
  FORCE_HEADERS = %w(From To Cc Bcc Subject)
  MULTI_HEADERS = %w(To Cc Bcc)
  NON_EDITABLE_HEADERS = %w(Message-Id Date)

  attr_reader :status

  register_keymap do |k|
    k.add :send_message, "Send message", 'y'
    k.add :edit, "Edit message", 'e', :enter
    k.add :save_as_draft, "Save as draft", 'P'
  end

  def initialize *a
    super
    @attachments = []
    @edited = false
  end

  def edit
    @file = Tempfile.new "sup.#{self.class.name.gsub(/.*::/, '').camel_to_hyphy}"
    @file.puts header_lines(header - NON_EDITABLE_HEADERS)
    @file.puts
    @file.puts body
    @file.close

    editor = $config[:editor] || ENV['EDITOR'] || "/usr/bin/vi"

    mtime = File.mtime @file.path
    BufferManager.shell_out "#{editor} #{@file.path}"
    @edited = true if File.mtime(@file.path) > mtime

    new_header, new_body = parse_file(@file.path)
    NON_EDITABLE_HEADERS.each { |h| new_header[h] = header[h] if header[h] }
    handle_new_text new_header, new_body
    update
  end

protected

  def gen_message_id
    "<#{Time.now.to_i}-sup-#{rand 10000}@#{Socket.gethostname}>"
  end

  def update
    regen_text
    buffer.mark_dirty
  end

  def parse_file fn
    File.open(fn) do |f|
      header = MBox::read_header f
      body = f.readlines

      header.delete_if { |k, v| NON_EDITABLE_HEADERS.member? k }
      header.each do |k, v|
        next unless MULTI_HEADERS.include?(k) && !v.empty?
        header[k] = v.split_on_commas.map do |name|
          (p = ContactManager.person_with(name)) && p.full_address || name
        end
      end

      [header, body]
    end
  end

  def header_lines header
    force_headers = FORCE_HEADERS.map { |h| make_lines "#{h}:", header[h] }
    other_headers = (header.keys - FORCE_HEADERS).map do |h|
      make_lines "#{h}:", header[h]
    end

    (force_headers + other_headers).flatten.compact
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
    return false unless @edited || BufferManager.ask_yes_or_no("Message unedited. Really send?")

    raise "no message id!" unless header["Message-Id"]
    date = Time.now
    from_email = 
      if header["From"] =~ /<?(\S+@(\S+?))>?$/
        $1
      else
        AccountManager.default_account.email
      end

    acct = AccountManager.account_for(from_email) || AccountManager.default_account
    SentManager.write_sent_message(date, from_email) { |f| write_message f, true, date }
    BufferManager.flash "sending..."

    IO.popen(acct.sendmail, "w") { |p| write_message p, true, date }

    BufferManager.kill_buffer buffer
    BufferManager.flash "Message sent!"
    true
  end

  def save_as_draft
    DraftManager.write_draft { |f| write_message f, false }
    BufferManager.kill_buffer buffer
    BufferManager.flash "Saved for later editing."
    true
  end

  def sig_lines
    sigfn = (AccountManager.account_for(header["From"]) || 
             AccountManager.default_account).sig_file

    if sigfn && File.exists?(sigfn)
      ["", "-- "] + File.readlines(sigfn).map { |l| l.chomp }
    else
      []
    end
  end

  def write_message f, full_header=true, date=Time.now
    raise ArgumentError, "no pre-defined date: header allowed" if header["Date"]
    f.puts header_lines(header)
    f.puts "Date: #{date.rfc2822}"
    if full_header
      f.puts <<EOS
Mime-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline
User-Agent: Redwood/#{Redwood::VERSION}
EOS
    end

    f.puts
    f.puts @body
  end  
end

end
