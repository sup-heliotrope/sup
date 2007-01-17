module Redwood

class ComposeMode < EditMessageMode
  attr_reader :body, :header

  def initialize opts={}
    super()
    @header = {
      "From" => AccountManager.default_account.full_address,
      "Message-Id" => gen_message_id,
    }

    @header["To"] = opts[:to].map { |p| p.full_address }.join(", ") if opts[:to]
    @header["Cc"] = opts[:cc].map { |p| p.full_address }.join(", ") if opts[:cc]
    @header["Bcc"] = opts[:bcc].map { |p| p.full_address }.join(", ") if opts[:bcc]
    @header["Subject"] = opts[:subj] if opts[:subj]

    @body = opts[:body] || sig_lines
    regen_text
  end

  def lines; @text.length; end
  def [] i; @text[i]; end

protected

  def handle_new_text new_header, new_body
    @header = new_header
    @body = new_body
  end

  def regen_text
    @text = header_lines(@header - EditMessageMode::NON_EDITABLE_HEADERS) + [""] + @body
  end
end

end
