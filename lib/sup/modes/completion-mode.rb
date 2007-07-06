module Redwood

class CompletionMode < ScrollMode
  INTERSTITIAL = "  "

  def initialize list, opts={}
    @list = list
    @header = opts[:header]
    @prefix_len = opts[:prefix_len]
    @lines = nil
    super :slip_rows => 1, :twiddles => false
  end

  def lines
    update_lines unless @lines
    @lines.length
  end

  def [] i
    update_lines unless @lines
    @lines[i]
  end

  def roll; if at_bottom? then jump_to_start else page_down end end

private

  def update_lines
    width = buffer.content_width
    max_length = @list.map { |s| s.length }.max
    num_per = buffer.content_width / (max_length + INTERSTITIAL.length)
    @lines = [@header].compact
    @list.each_with_index do |s, i|
      if @prefix_len
        @lines << [] if i % num_per == 0
        if @prefix_len < s.length
          prefix = s[0 ... @prefix_len]
          suffix = s[(@prefix_len + 1) .. -1]
          char = s[@prefix_len].chr

          @lines.last += [[:none, sprintf("%#{max_length - suffix.length - 1}s", prefix)],
                          [:completion_character_color, char],
                          [:none, suffix + INTERSTITIAL]]
        else
          @lines.last += [[:none, sprintf("%#{max_length}s#{INTERSTITIAL}", s)]]
        end
      else
        @lines << "" if i % num_per == 0
        @lines.last += sprintf "%#{max_length}s#{INTERSTITIAL}", s
      end
    end
  end
end

end
