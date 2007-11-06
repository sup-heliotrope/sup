module Redwood

class Keymap
  def initialize
    @map = {}
    @order = []
    yield self if block_given?
  end

  def keysym_to_keycode k
    case k
    when :down: Curses::KEY_DOWN
    when :up: Curses::KEY_UP
    when :left: Curses::KEY_LEFT
    when :right: Curses::KEY_RIGHT
    when :page_down: Curses::KEY_NPAGE
    when :page_up: Curses::KEY_PPAGE
    when :backspace: Curses::KEY_BACKSPACE
    when :home: Curses::KEY_HOME
    when :end: Curses::KEY_END
    when :ctrl_l: "\f"[0]
    when :ctrl_g: "\a"[0]
    when :tab: "\t"[0]
    when :enter, :return: 10 #Curses::KEY_ENTER
    else
      if k.is_a?(String) && k.length == 1
        k[0]
      else
        raise ArgumentError, "unknown key name '#{k}'"
      end
    end
  end

  def keysym_to_string k
    case k
    when :down: "<down arrow>"
    when :up: "<up arrow>"
    when :left: "<left arrow>"
    when :right: "<right arrow>"
    when :page_down: "<page down>"
    when :page_up: "<page up>"
    when :backspace: "<backspace>"
    when :home: "<home>"
    when :end: "<end>"
    when :enter, :return: "<enter>"
    when :ctrl_l: "ctrl-l"
    when :ctrl_g: "ctrl-g"
    when :tab: "tab"
    when " ": "<space>"
    else
      if k.is_a?(String) && k.length == 1
        k
      else
        raise ArgumentError, "unknown key name \"#{k}\""
      end
    end
  end

  def add action, help, *keys
    entry = [action, help, keys]
    @order << entry
    keys.each do |k|
      raise ArgumentError, "key #{k} already defined (action #{action})" if @map.include? k
      kc = keysym_to_keycode k
      @map[kc] = entry
    end
  end

  def action_for kc
    action, help, keys = @map[kc]
    action
  end

  def keysyms; @map.values.map { |action, help, keys| keys }.flatten; end

  def help_text except_for={}
    lines = @order.map do |action, help, keys|
      valid_keys = keys.select { |k| !except_for[k] }
      next if valid_keys.empty?
      [valid_keys.map { |k| keysym_to_string k }.join(", "), help]
    end.compact
    llen = lines.max_of { |a, b| a.length }
    lines.map { |a, b| sprintf " %#{llen}s : %s", a, b }.join("\n")
  end
end

end
