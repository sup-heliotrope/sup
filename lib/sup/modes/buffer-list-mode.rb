module Redwood

class BufferListMode < LineCursorMode
  register_keymap do |k|
    k.add :jump_to_buffer, "Jump to selected buffer", :enter
    k.add :reload, "Reload buffer list", "R"
  end

  def initialize
    regen_text
    super
  end

  def lines; @text.length; end
  def [] i; @text[i]; end

protected

  def reload
    regen_text
    buffer.mark_dirty
  end

  def regen_text
    @bufs = BufferManager.buffers.sort_by { |name, buf| name }
    width = @bufs.max_of { |name, buf| buf.mode.name.length }
    @text = @bufs.map do |name, buf|
      sprintf "%#{width}s  %s", buf.mode.name, name
    end
  end

  def jump_to_buffer
    BufferManager.raise_to_front @bufs[curpos][1]
  end
end

end
