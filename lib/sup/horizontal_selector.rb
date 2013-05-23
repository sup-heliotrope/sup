module Redwood

class HorizontalSelector
  class UnknownValue < StandardError; end

  attr_accessor :label, :changed_by_user

  def initialize label, vals, labels, base_color=:horizontal_selector_unselected_color, selected_color=:horizontal_selector_selected_color
    @label = label
    @vals = vals
    @labels = labels
    @base_color = base_color
    @selected_color = selected_color
    @selection = 0
    @changed_by_user = false
  end

  def set_to val
    raise UnknownValue, val.inspect unless can_set_to? val
    @selection = @vals.index(val)
  end

  def can_set_to? val
    @vals.include? val
  end

  def val; @vals[@selection] end

  def line width=nil
    label =
      if width
        sprintf "%#{width}s ", @label
      else
        "#{@label} "
      end

    [[@base_color, label]] +
      (0 ... @labels.length).inject([]) do |array, i|
        array + [
          if i == @selection
            [@selected_color, @labels[i]]
          else
            [@base_color, @labels[i]]
          end] + [[@base_color, "  "]]
      end + [[@base_color, ""]]
  end

  def roll_left
    @selection = (@selection - 1) % @labels.length
    @changed_by_user = true
  end

  def roll_right
    @selection = (@selection + 1) % @labels.length
    @changed_by_user = true
  end
end

end
