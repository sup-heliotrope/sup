module Redwood

class BufferListMode < LineCursorMode
  register_keymap do |k|
    k.add :jump_to_buffer, "Jump to that buffer", :enter
    k.add :reload, "Reload", "R"
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
    width = @bufs.map { |name, buf| name.length }.max
    @text = @bufs.map do |name, buf|
      sprintf "%#{width}s  %s", name, buf.mode.name
    end
  end

  def jump_to_buffer
    BufferManager.raise_to_front @bufs[curpos][1]
  end
end

end
