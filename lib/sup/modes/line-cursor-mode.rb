module Redwood

class LineCursorMode < ScrollMode
  register_keymap do |k|
    ## overwrite scrollmode binding on arrow keys for cursor movement
    ## but j and k still scroll!
    k.add :cursor_down, "Move cursor down one line", :down, 'j'
    k.add :cursor_up, "Move cursor up one line", :up, 'k'
    k.add :select, "Select this item", :enter
  end

  attr_reader :curpos

  def initialize cursor_top=0, opts={}
    @cursor_top = cursor_top
    @curpos = cursor_top
    super opts
  end

  def draw
    super
    set_status
  end

protected

  def draw_line ln, opts={}
    if ln == @curpos
      super ln, :highlight => true, :debug => opts[:debug]
    else
      super
    end
  end

  def ensure_mode_validity
    super
    raise @curpos.inspect unless @curpos.is_a?(Integer)
    c = @curpos.clamp topline, botline - 1
    c = @cursor_top if c < @cursor_top
    buffer.mark_dirty unless c == @curpos
    @curpos = c
  end

  def set_cursor_pos p
    return if @curpos == p
    @curpos = p.clamp @cursor_top, lines
    buffer.mark_dirty
  end

  def line_down # overwrite scrollmode
    super
    set_cursor_pos topline if @curpos < topline
  end

  def line_up # overwrite scrollmode
    super
    set_cursor_pos botline - 1 if @curpos > botline - 1
  end

  def cursor_down
    return false unless @curpos < lines - 1
    if @curpos >= botline - 1
      page_down
      set_cursor_pos [topline + 1, botline].min
    else
      @curpos += 1
      unless buffer.dirty?
        draw_line @curpos - 1
        draw_line @curpos
        set_status
        buffer.commit
      end
    end
    true
  end

  def cursor_up
    return false unless @curpos > @cursor_top
    if @curpos == topline
      page_up
      set_cursor_pos [botline - 2, topline].max
    else
      @curpos -= 1
      unless buffer.dirty?
        draw_line @curpos + 1
        draw_line @curpos
        set_status
        buffer.commit
      end
    end
    true
  end

  def page_up # overwrite
    if topline <= @cursor_top
      set_cursor_pos @cursor_top
    else
      relpos = @curpos - topline
      super
      set_cursor_pos topline + relpos
    end
  end

  def page_down
    if topline >= lines - buffer.content_height
      set_cursor_pos(lines - 1)
    else
      relpos = @curpos - topline
      super
      set_cursor_pos [topline + relpos, lines - 1].min
    end
  end

  def jump_to_home
    super
    set_cursor_pos @cursor_top
  end

  def jump_to_end
    super if topline < (lines - buffer.content_height)
    set_cursor_pos(lines - 1)
  end

private

  def set_status
    l = lines
    @status = l > 0 ? "line #{@curpos + 1} of #{l}" : ""
  end

end

end
