module Redwood

class ScrollMode < Mode
  ## we define topline and botline as the top and bottom lines of any
  ## content in the currentview.
  
  ## we left leftcol and rightcol as the left and right columns of any
  ## content in the current view. but since we're operating in a
  ## line-centric fashion, rightcol is always leftcol + the buffer
  ## width. (whereas botline is topline + at most the buffer height,
  ## and can be == to topline in the case that there's no content.)

  attr_reader :status, :topline, :botline, :leftcol

  COL_JUMP = 2

  register_keymap do |k|
    k.add :line_down, "Down one line", :down, 'j', 'J'
    k.add :line_up, "Up one line", :up, 'k', 'K'
    k.add :col_left, "Left one column", :left, 'h'
    k.add :col_right, "Right one column", :right, 'l'
    k.add :page_down, "Down one page", :page_down, ' '
    k.add :page_up, "Up one page", :page_up, 'p', :backspace
    k.add :jump_to_start, "Jump to top", :home, '^', '1'
    k.add :jump_to_end, "Jump to bottom", :end, '$', '0'
    k.add :jump_to_left, "Jump to the left", '['
    k.add :search_in_buffer, "Search in current buffer", '/'
    k.add :continue_search_in_buffer, "Jump to next search occurrence in buffer", BufferManager::CONTINUE_IN_BUFFER_SEARCH_KEY
  end

  def initialize opts={}
    @topline, @botline, @leftcol = 0, 0, 0
    @slip_rows = opts[:slip_rows] || 0 # when we pgup/pgdown,
                                       # how many lines do we keep?
    @twiddles = opts.member?(:twiddles) ? opts[:twiddles] : true
    @search_query = nil
    @search_line = nil
    @status = ""
    super()
  end

  def rightcol; @leftcol + buffer.content_width; end

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

  def in_search?; @search_line end
  def cancel_search!; @search_line = nil end

  def continue_search_in_buffer
    unless @search_query
      BufferManager.flash "No current search!"
      return
    end

    start = @search_line || search_start_line
    line = find_text @search_query, start
    if line.nil? && (start > 0)
      line = find_text @search_query, 0
      BufferManager.flash "Search wrapped to top!" if line
    end
    if line
      @search_line = line + 1
      search_goto_line line
      buffer.mark_dirty
    else
      BufferManager.flash "Not found!"
    end
  end

  def search_in_buffer
    query = BufferManager.ask :search, "search in buffer: "
    return if query.nil? || query.empty?
    @search_query = Regexp.escape query
    continue_search_in_buffer
  end

  ## subclasses can override these two!
  def search_goto_line line; jump_to_line line end
  def search_start_line; @topline end

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

  def at_top?; @topline == 0 end
  def at_bottom?; @botline == lines end

  def line_down; jump_to_line @topline + 1; end
  def line_up;  jump_to_line @topline - 1; end
  def page_down; jump_to_line @topline + buffer.content_height - @slip_rows; end
  def page_up; jump_to_line @topline - buffer.content_height + @slip_rows; end
  def jump_to_start; jump_to_line 0; end
  def jump_to_end; jump_to_line lines - buffer.content_height; end

  def ensure_mode_validity
    @topline = @topline.clamp 0, [lines - 1, 0].max
    @botline = [@topline + buffer.content_height, lines].min
  end

  def resize *a
    super(*a)
    ensure_mode_validity
  end

protected

  def find_text query, start_line
    regex = /#{query}/i
    (start_line ... lines).each do |i|
      case(s = self[i])
      when String
        return i if s =~ regex
      when Array
        return i if s.any? { |color, string| string =~ regex }
      end
    end
    nil
  end

  def draw_line ln, opts={}
    regex = /(#{@search_query})/i
    case(s = self[ln])
    when String
      if in_search?
        draw_line_from_array ln, matching_text_array(s, regex), opts
      else
        draw_line_from_string ln, s, opts
      end
    when Array
      if in_search?
        ## seems like there ought to be a better way of doing this
        array = []
        s.each do |color, text| 
          if text =~ regex
            array += matching_text_array text, regex, color
          else
            array << [color, text]
          end
        end
        draw_line_from_array ln, array, opts
      else
        draw_line_from_array ln, s, opts
      end
    else
      raise "unknown drawable object: #{s.inspect} in #{self} for line #{ln}" # good for debugging
    end

      ## speed test
      # str = s.map { |color, text| text }.join
      # buffer.write ln - @topline, 0, str, :color => :none, :highlight => opts[:highlight]
      # return
  end

  def matching_text_array s, regex, oldcolor=:none
    s.split(regex).map do |text|
      next if text.empty?
      if text =~ regex
        [:search_highlight_color, text]
      else
        [oldcolor, text]
      end
    end.compact + [[oldcolor, ""]]
  end

  def draw_line_from_array ln, a, opts
    xpos = 0
    a.each do |color, text|
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

  def draw_line_from_string ln, s, opts
    buffer.write ln - @topline, 0, s[@leftcol .. -1], :highlight => opts[:highlight]
  end
end

end

