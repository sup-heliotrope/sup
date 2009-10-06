module Redwood

class BufferListMode < LineCursorMode
  include M17n

  register_keymap do |k|
    k.add :jump_to_buffer, m('buffer_list.keymap.jump_to_buffer'), :enter
    k.add :reload, m('buffer_list.keymap.reload_list'), "@"
  end

  def initialize
    regen_text
    super
  end

  def lines; @text.length end
  def [] i; @text[i] end

  def focus
    reload # buffers may have been killed or created since last view
    set_cursor_pos 0
  end

protected

  def reload
    regen_text
    buffer.mark_dirty
  end

  def regen_text
    @bufs = BufferManager.buffers.reject { |name, buf| buf.mode == self }.sort_by { |name, buf| buf.atime }.reverse
    width = @bufs.max_of { |name, buf| buf.mode.name.length }
    @text = @bufs.map do |name, buf|
      base_color = buf.system? ? :system_buf_color : :regular_buf_color
      [[base_color, sprintf("%#{width}s ", buf.mode.name)],
       [:modified_buffer_color, (buf.mode.unsaved? ? '*' : ' ')],
       [base_color, " " + name]]
    end
  end

  def jump_to_buffer
    BufferManager.raise_to_front @bufs[curpos][1]
  end
end

end
