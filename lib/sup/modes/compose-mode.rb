module Redwood

class ComposeMode < EditMessageMode
  attr_reader :body, :header

  def initialize h={}
    super()
    @header = {
      "From" => AccountManager.default_account.full_address,
      "Message-Id" => gen_message_id,
    }

    @header["To"] = [h[:to]].flatten.compact.map { |p| p.full_address }
    @body = sig_lines
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
