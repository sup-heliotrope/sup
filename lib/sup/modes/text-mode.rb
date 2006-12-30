module Redwood

class TextMode < ScrollMode
  attr_reader :text

  def initialize text=""
    @text = text.normalize_whitespace
    update_lines
    buffer.mark_dirty if buffer
    super()
  end

  def text= t
    @text = t
    update_lines
    if buffer
      ensure_mode_validity
      buffer.mark_dirty 
    end
  end

  def << line
    @lines = [0] if @text.empty?
    @text << line
    @lines << @text.length
    if buffer
      ensure_mode_validity
      buffer.mark_dirty 
    end
  end

  def lines
    @lines.length - 1
  end

  def [] i
    return nil unless i < @lines.length
    @text[@lines[i] ... (i + 1 < @lines.length ? @lines[i + 1] - 1 : @text.length)]
#    (@lines[i] ... (i + 1 < @lines.length ? @lines[i + 1] - 1 : @text.length)).inspect
  end

private

  def update_lines
    pos = @text.find_all_positions("\n")
    pos.push @text.length unless pos.last == @text.length - 1
    @lines = [0] + pos.map { |x| x + 1 }
  end
end

end
