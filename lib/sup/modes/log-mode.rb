module Redwood

class LogMode < TextMode
  register_keymap do |k|
    k.add :toggle_follow, "Toggle follow mode", 'f'
  end

  def initialize
    @follow = true
    super ""
  end

  def toggle_follow
    @follow = !@follow
    if buffer
      if @follow
        jump_to_line lines - buffer.content_height + 1 # leave an empty line at bottom
      end
      buffer.mark_dirty
    end
  end

  def text= t
    super
    if buffer && @follow
      follow_top = lines - buffer.content_height + 1
      jump_to_line follow_top if topline < follow_top
    end
  end

  def << line
    super
    if buffer && @follow
      follow_top = lines - buffer.content_height + 1
      jump_to_line follow_top if topline < follow_top
    end
  end

  def status
    super + " (follow: #@follow)"
  end
end

end
