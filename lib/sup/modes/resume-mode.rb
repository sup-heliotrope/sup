module Redwood

class ResumeMode < ComposeMode
  def initialize m
    super()
    @id = m.id
    @header, @body = parse_file m.draft_filename
    @header.delete "Date"
    @header["Message-Id"] = gen_message_id # generate a new'n
    regen_text
    @safe = false
  end

  def killable?
    unless @safe
      case BufferManager.ask_yes_or_no "Discard draft?"
      when true
        DraftManager.discard @id
        BufferManager.flash "Draft discarded."
        true
      when false
        BufferManager.flash "Draft saved."
        true
      else
        false
      end
    end
  end

  def send_message
    if super
      DraftManager.discard @id 
      @safe = true
    end
  end

  def save_as_draft
    @safe = true
    DraftManager.discard @id if super
  end
end

end
