module Redwood

class ResumeMode < ComposeMode
  def initialize m
    super()
    @id = m.id
    @header, @body = parse_file m.draft_filename
    @header.delete "Date"
    @header["Message-Id"] = gen_message_id # generate a new'n
    regen_text
  end

  def send_message
    DraftManager.discard @id if super
  end
end

end
