module Redwood

class HorizontalSelector
  attr_accessor :label

  def initialize label, vals, labels, base_color=:horizontal_selector_unselected_color, selected_color=:horizontal_selector_selected_color
    @label = label
    @vals = vals
    @labels = labels
    @base_color = base_color
    @selected_color = selected_color
    @selection = 0
  end

  def set_to val; @selection = @vals.index(val) end

  def val; @vals[@selection] end

  def old_line width=nil
    label =
      if width
        sprintf "%#{width}s ", @label
      else
        "#{@label} "
      end

    [[:none, label]] + 
      (0 ... @labels.length).inject([]) do |array, i|
        array + [
          if i == @selection
            [@selected_color, "[" + @labels[i] + "]"]
          else
            [@base_color, " " + @labels[i] + " "]
          end] + [[:none, " "]]
      end + [[:none, ""]]
  end

  def line width=nil
    label =
      if width
        sprintf "%#{width}s ", @label
      else
        "#{@label} "
      end

    [[:none, label]] + 
      (0 ... @labels.length).inject([]) do |array, i|
        array + [
          if i == @selection
            [@selected_color, @labels[i]]
          else
            [@base_color, @labels[i]]
          end] + [[:none, "  "]]
      end + [[:none, ""]]
  end

  def roll_left
    @selection = (@selection - 1) % @labels.length
  end

  def roll_right
    @selection = (@selection + 1) % @labels.length
  end
end

end
