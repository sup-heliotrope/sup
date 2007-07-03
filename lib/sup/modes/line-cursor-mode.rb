module Redwood

## extends ScrollMode to have a line-based cursor.
class LineCursorMode < ScrollMode
  register_keymap do |k|
    ## overwrite scrollmode binding on arrow keys for cursor movement
    ## but j and k still scroll!
    k.add :cursor_down, "Move cursor down one line", :down, 'j'
    k.add :cursor_up, "Move cursor up one line", :up, 'k'
    k.add :select, "Select this item", :enter
  end

  attr_reader :curpos

  def initialize opts={}
    @cursor_top = @curpos = opts[:skip_top_rows] || 0
    @load_more_callbacks = []
    @load_more_callbacks_m = Mutex.new
    @load_more_callbacks_active = false
    super opts
  end

  def draw
    super
    set_status
  end

protected

  ## callbacks when the cursor is asked to go beyond the bottom
  def to_load_more &b
    @load_more_callbacks << b
  end

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
    call_load_more_callbacks([topline + buffer.content_height - lines, 10].max) if topline + buffer.content_height > lines
    set_cursor_pos topline if @curpos < topline
  end

  def line_up # overwrite scrollmode
    super
    set_cursor_pos botline - 1 if @curpos > botline - 1
  end

  def cursor_down
    call_load_more_callbacks buffer.content_height if @curpos == lines - 1
    return false unless @curpos < lines - 1

    if @curpos >= botline - 1
      page_down
      set_cursor_pos topline
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
      old_topline = topline
      page_up
      set_cursor_pos [old_topline - 1, topline].max
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

  ## more complicated than one might think. three behaviors.
  def page_down
    ## if we're on the last page, and it's not a full page, just move
    ## the cursor down to the bottom and assume we can't load anything
    ## else via the callbacks.
    if topline > lines - buffer.content_height
      set_cursor_pos(lines - 1)

    ## if we're on the last page, and it's a full page, try and load
    ## more lines via the callbacks and then shift the page down
    elsif topline == lines - buffer.content_height
      call_load_more_callbacks buffer.content_height
      super

    ## otherwise, just move down
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

  def call_load_more_callbacks size
    go = 
      @load_more_callbacks_m.synchronize do
        if @load_more_callbacks_active
          false
        else
          @load_more_callbacks_active = true
        end
    end

    return unless go

    @load_more_callbacks.each { |c| c.call size }
    @load_more_callbacks_active = false
  end    

end

end
