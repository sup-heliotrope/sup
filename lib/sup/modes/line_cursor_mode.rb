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
    @cursor_top = @curpos = opts.delete(:skip_top_rows) || 0
    @load_more_callbacks = []
    @load_more_q = Queue.new
    @load_more_thread = ::Thread.new do
      while true
        e = @load_more_q.pop
        @load_more_callbacks.each { |c| c.call e }
        hysteresis = $config[:load_more_threads_hysteresis] || 0.5
        if hysteresis > 0 then
          sleep hysteresis
          @load_more_q.pop until @load_more_q.empty?
        end
      end
    end

    super opts
  end

  def spawned; call_load_more_callbacks buffer.content_height + 1; end

  def cleanup
    @load_more_thread.kill
    super
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
      super ln, :highlight => true, :debug => opts[:debug], :color => :text_color
    else
      super ln, :color => :text_color
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
    buffer.mark_dirty if buffer # not sure why the buffer is gone
    set_status
  end

  ## override search behavior to be cursor-based. this is a stupid
  ## implementation and should be made better. TODO: improve.
  def search_goto_line line
    page_down while line >= botline
    page_up while line < topline
    set_cursor_pos line
  end

  def search_start_line; @curpos end

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
    call_load_more_callbacks buffer.content_height if @curpos >= lines - [buffer.content_height/2,1].max
    return false unless @curpos < lines - 1

    if $config[:continuous_scroll] and (@curpos == botline - 3 and @curpos < lines - 3)
      # load more lines, one at a time.
      jump_to_line topline + 1
      @curpos += 1
      unless buffer.dirty?
        draw_line @curpos - 1
        draw_line @curpos
        set_status
        buffer.commit
      end
    elsif @curpos >= botline - 1
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

    if $config[:continuous_scroll] and (@curpos == topline + 2)
      jump_to_line topline - 1
      @curpos -= 1
      unless buffer.dirty?
        draw_line @curpos + 1
        draw_line @curpos
        set_status
        buffer.commit
      end
    elsif @curpos == topline
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

  def half_page_up
    super
    set_cursor_pos [botline, @curpos].min
  end

  def page_down
    relpos = @curpos - topline
    super
    set_cursor_pos [topline + relpos, lines - 1].min
    call_load_more_callbacks buffer.content_height if lines < topline + buffer.content_height
  end

  def half_page_down
    super
    set_cursor_pos [topline, @curpos].max
  end

  def jump_to_start
    super
    set_cursor_pos @cursor_top
  end

  def jump_to_end
    super if topline < (lines - buffer.content_height)
    set_cursor_pos(lines - 1)
    call_load_more_callbacks buffer.content_height
  end

private

  def set_status
    l = lines
    @status = l > 0 ? "line #{@curpos + 1} of #{l}" : ""
  end

  def call_load_more_callbacks size
    @load_more_q.push size if $config[:load_more_threads_when_scrolling]
  end
end
end
