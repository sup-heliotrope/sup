module Redwood

class ForwardMode < EditMessageMode
  def initialize m
    super :header => {
      "From" => AccountManager.default_account.full_address,
      "Subject" => "Fwd: #{m.subj}",
    },
         :body => forward_body_lines(m)
  end

protected

  def forward_body_lines m
    ["--- Begin forwarded message from #{m.from.mediumname} ---"] + 
      m.basic_header_lines + [""] + m.basic_body_lines +
      ["--- End forwarded message ---"]
  end
end

end
