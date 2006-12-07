module Redwood

class ResumeMode < ComposeMode
  def initialize m
    super()
    @id = m.id
    @header, @body = parse_file m.draft_filename
    @header.delete "Date"
    @header["Message-Id"] = gen_message_id # generate a new'n
    regen_text
    @sent = false
  end

  def send_message
    if super
      DraftManager.discard @id 
      @sent = true
    end
  end

  def cleanup
    unless @sent
      if BufferManager.ask_yes_or_no "discard draft?"
        DraftManager.discard @id
        BufferManager.flash "Draft discarded."
      else
        BufferManager.flash "Draft saved."
      end
      super
    end
  end
end

end
