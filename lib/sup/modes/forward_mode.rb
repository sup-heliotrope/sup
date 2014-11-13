module Redwood

class ForwardMode < EditMessageMode

  HookManager.register "forward-attribution", <<EOS
Generates the attribution for the forwarded message
(["--- Begin forwarded message from John Doe ---",
  "--- End forwarded message ---"])
Variables:
  message: a message object representing the message being replied to
    (useful values include message.from.mediumname and message.date)
Return value:
  A list containing two strings: the text of the begin line and the text of the end line
EOS
  ## TODO: share some of this with reply-mode
  def initialize opts={}
    header = {
      "From" => AccountManager.default_account.full_address,
    }

    @m = opts[:message]
    header["Subject"] =
      if @m
        "Fwd: " + @m.subj
      elsif opts[:attachments]
        "Fwd: " + opts[:attachments].keys.join(", ")
      end

    header["To"] = opts[:to].map { |p| p.full_address }.join(", ") if opts[:to]
    header["Cc"] = opts[:cc].map { |p| p.full_address }.join(", ") if opts[:cc]
    header["Bcc"] = opts[:bcc].map { |p| p.full_address }.join(", ") if opts[:bcc]

    body =
      if @m
        forward_body_lines @m
      elsif opts[:attachments]
        ["Note: #{opts[:attachments].size.pluralize 'attachment'}."]
      end

    super :header => header, :body => body, :attachments => opts[:attachments]
  end

  def self.spawn_nicely opts={}
    to = opts[:to] || (BufferManager.ask_for_contacts(:people, "To: ") or return if ($config[:ask_for_to] != false))
    cc = opts[:cc] || (BufferManager.ask_for_contacts(:people, "Cc: ") or return if $config[:ask_for_cc])
    bcc = opts[:bcc] || (BufferManager.ask_for_contacts(:people, "Bcc: ") or return if $config[:ask_for_bcc])

    attachment_hash = {}
    attachments = opts[:attachments] || []

    if(m = opts[:message])
      m.load_from_source! # read the full message in. you know, maybe i should just make Message#chunks do this....
      attachments += m.chunks.select { |c| c.is_a?(Chunk::Attachment) && !c.quotable? }
    end

    attachments.each do |c|
      mime_type = MIME::Types[c.content_type].first || MIME::Types["application/octet-stream"].first
      attachment_hash[c.filename] = RMail::Message.make_attachment c.raw_content, mime_type.content_type, mime_type.encoding, c.filename
    end

    mode = ForwardMode.new :message => opts[:message], :to => to, :cc => cc, :bcc => bcc, :attachments => attachment_hash

    title = "Forwarding " +
      if opts[:message]
        opts[:message].subj
      elsif attachments
        attachment_hash.keys.join(", ")
      else
        "something"
      end

    BufferManager.spawn title, mode
    mode.default_edit_message
  end

protected

  def forward_body_lines m
    attribution = HookManager.run("forward-attribution", :message => m) || default_attribution(m)
    attribution[0,1] +
    m.quotable_header_lines +
    [""] +
    m.quotable_body_lines +
    attribution[1,1]
  end

  def default_attribution m
    ["--- Begin forwarded message from #{m.from.mediumname} ---",
     "--- End forwarded message ---"]
  end

  def send_message
    return unless super # super returns true if the mail has been sent
    if @m
      @m.add_label :forwarded
      Index.save_message @m
    end
  end
end

end
