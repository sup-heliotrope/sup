module Redwood

class ForwardMode < EditMessageMode
  attr_reader :body, :header

  def initialize m
    super()
    @header = {
      "From" => AccountManager.default_account.full_address,
      "Subject" => "Fwd: #{m.subj}",
      "Message-Id" => gen_message_id,
    }
    @body = forward_body_lines m
    regen_text
  end

protected

  def forward_body_lines m
    ["--- Begin forwarded message from #{m.from.mediumname} ---"] + 
      m.basic_header_lines + [""] + m.basic_body_lines +
      ["--- End forwarded message ---"]
  end

  def handle_new_text new_header, new_body
    @header = new_header
    @body = new_body
  end
end

end
