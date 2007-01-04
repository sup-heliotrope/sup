module Redwood

class ScrollMode < Mode
  attr_reader :status, :topline, :botline

  COL_JUMP = 2

  register_keymap do |k|
    k.add :line_down, "Down one line", :down, 'j', 'J'
    k.add :line_up, "Up one line", :up, 'k', 'K'
    k.add :col_left, "Left one column", :left, 'h'
    k.add :col_right, "Right one column", :right, 'l'
    k.add :page_down, "Down one page", :page_down, 'n', ' '
    k.add :page_up, "Up one page", :page_up, 'p', :backspace
    k.add :jump_to_home, "Jump to top", :home, '^', '1'
    k.add :jump_to_end, "Jump to bottom", :end, '$', '0'
    k.add :jump_to_left, "Jump to the left", '['
  end

  def initialize opts={}
    @topline, @botline, @leftcol = 0, 0, 0
    @slip_rows = opts[:slip_rows] || 0 # when we pgup/pgdown,
                                       # how many lines do we keep?
    @twiddles = opts.member?(:twiddles) ? opts[:twiddles] : true
    super()
  end

  def draw
    ensure_mode_validity
    (@topline ... @botline).each { |ln| draw_line ln }
    ((@botline - @topline) ... buffer.content_height).each do |ln|
      if @twiddles
        buffer.write ln, 0, "~", :color => :twiddle_color
      else
        buffer.write ln, 0, ""
      end
    end
    @status = "lines #{@topline + 1}:#{@botline}/#{lines}"
  end

  def col_left
    return unless @leftcol > 0
    @leftcol -= COL_JUMP
    buffer.mark_dirty
  end

  def col_right
    @leftcol += COL_JUMP
    buffer.mark_dirty
  end

  def jump_to_col col
    buffer.mark_dirty unless @leftcol == col
    @leftcol = col
  end

  def jump_to_left; jump_to_col 0; end

  ## set top line to l
  def jump_to_line l
    l = l.clamp 0, lines - 1
    return if @topline == l
    @topline = l
    @botline = [l + buffer.content_height, lines].min
    buffer.mark_dirty
  end

  def line_down; jump_to_line @topline + 1; end
  def line_up;  jump_to_line @topline - 1; end
  def page_down; jump_to_line @topline + buffer.content_height - @slip_rows; end
  def page_up; jump_to_line @topline - buffer.content_height + @slip_rows; end
  def jump_to_home; jump_to_line 0; end
  def jump_to_end; jump_to_line lines - buffer.content_height; end


  def ensure_mode_validity
    @topline = @topline.clamp 0, lines - 1
    @topline = 0 if @topline < 0 # empty 
    @botline = [@topline + buffer.content_height, lines].min
  end

  def resize *a
    super *a
    ensure_mode_validity
  end

protected

  def draw_line ln, opts={}
    case(s = self[ln])
    when String
      buffer.write ln - @topline, 0, s[@leftcol .. -1],
                   :highlight => opts[:highlight]
    when Array
      xpos = 0

      ## speed test
      # str = s.map { |color, text| text }.join
      # buffer.write ln - @topline, 0, str, :color => :none, :highlight => opts[:highlight]
      # return

      s.each do |color, text|
        raise "nil text for color '#{color}'" if text.nil? # good for debugging
        if xpos + text.length < @leftcol
          buffer.write ln - @topline, 0, "", :color => color,
                       :highlight => opts[:highlight]
          xpos += text.length
        elsif xpos < @leftcol
          ## partial
          buffer.write ln - @topline, 0, text[(@leftcol - xpos) .. -1],
                       :color => color,
                       :highlight => opts[:highlight]
          xpos += text.length
        else
          buffer.write ln - @topline, xpos - @leftcol, text,
                       :color => color, :highlight => opts[:highlight]
          xpos += text.length
        end

      end
    end
  end
end

end
