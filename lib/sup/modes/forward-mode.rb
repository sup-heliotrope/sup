module Redwood

class ForwardMode < EditMessageMode
  ## TODO: share some of this with reply-mode
  def initialize opts={}
    header = {
      "From" => AccountManager.default_account.full_address,
    }

    header["Subject"] = 
      if opts[:message]
        "Fwd: " + opts[:message].subj
      elsif opts[:attachments]
        "Fwd: " + opts[:attachments].keys.join(", ")
      end

    header["To"] = opts[:to].map { |p| p.full_address }.join(", ") if opts[:to]
    header["Cc"] = opts[:cc].map { |p| p.full_address }.join(", ") if opts[:cc]
    header["Bcc"] = opts[:bcc].map { |p| p.full_address }.join(", ") if opts[:bcc]

    body =
      if opts[:message]
        forward_body_lines(opts[:message]) 
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
    mode.edit_message
  end

protected

  def forward_body_lines m
    ["--- Begin forwarded message from #{m.from.mediumname} ---"] + 
      m.quotable_header_lines + [""] + m.quotable_body_lines +
      ["--- End forwarded message ---"]
  end
end

end
