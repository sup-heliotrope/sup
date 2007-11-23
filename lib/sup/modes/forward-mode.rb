module Redwood

module CanSpawnForwardMode
  def spawn_forward_mode m, opts={}
    to = opts[:to] || BufferManager.ask_for_contacts(:people, "To: ") or return
    cc = opts[:cc] || BufferManager.ask_for_contacts(:people, "Cc: ") or return if $config[:ask_for_cc]
    bcc = opts[:bcc] || BufferManager.ask_for_contacts(:people, "Bcc: ") or return if $config[:ask_for_bcc]
    
    mode = ForwardMode.new m, :to => to, :cc => cc, :bcc => bcc
    BufferManager.spawn "Forwarding #{m.subj}", mode
    mode.edit_message
  end
end

class ForwardMode < EditMessageMode

  ## todo: share some of this with reply-mode
  def initialize m, opts={}
    header = {
      "From" => AccountManager.default_account.full_address,
      "Subject" => "Fwd: #{m.subj}",
    }

    header["To"] = opts[:to].map { |p| p.full_address }.join(", ") if opts[:to]
    header["Cc"] = opts[:cc].map { |p| p.full_address }.join(", ") if opts[:cc]
    header["Bcc"] = opts[:bcc].map { |p| p.full_address }.join(", ") if opts[:bcc]

    super :header => header, :body => forward_body_lines(m)
  end

protected

  def forward_body_lines m
    ["--- Begin forwarded message from #{m.from.mediumname} ---"] + 
      m.quotable_header_lines + [""] + m.quotable_body_lines +
      ["--- End forwarded message ---"]
  end
end

end
