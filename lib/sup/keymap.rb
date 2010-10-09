module Redwood

class Keymap

  HookManager.register "keybindings", <<EOS
Add custom keybindings.
Methods:
  modes: Hash from mode names to mode classes.
  global_keymap: The top-level keymap.
EOS

  def initialize
    @map = {}
    @order = []
    yield self if block_given?
  end

  def self.keysym_to_keycode k
    case k
    when :down then Curses::KEY_DOWN
    when :up then Curses::KEY_UP
    when :left then Curses::KEY_LEFT
    when :right then Curses::KEY_RIGHT
    when :page_down then Curses::KEY_NPAGE
    when :page_up then Curses::KEY_PPAGE
    when :backspace then Curses::KEY_BACKSPACE
    when :home then Curses::KEY_HOME
    when :end then Curses::KEY_END
    when :ctrl_l then "\f".ord
    when :ctrl_g then "\a".ord
    when :tab then "\t".ord
    when :enter, :return then 10 #Curses::KEY_ENTER
    else
      if k.is_a?(String) && k.length == 1
        k.ord
      else
        raise ArgumentError, "unknown key name '#{k}'"
      end
    end
  end

  def self.keysym_to_string k
    case k
    when :down then "<down arrow>"
    when :up then "<up arrow>"
    when :left then "<left arrow>"
    when :right then "<right arrow>"
    when :page_down then "<page down>"
    when :page_up then "<page up>"
    when :backspace then "<backspace>"
    when :home then "<home>"
    when :end then "<end>"
    when :enter, :return then "<enter>"
    when :tab then "tab"
    when " " then "<space>"
    else
      Curses::keyname(keysym_to_keycode(k))
    end
  end

  def add action, help, *keys
    entry = [action, help, keys]
    @order << entry
    keys.each do |k|
      kc = Keymap.keysym_to_keycode k
      raise ArgumentError, "key '#{k}' already defined (as #{@map[kc].first})" if @map.include? kc
      @map[kc] = entry
    end
  end

  def delete k
    kc = Keymap.keysym_to_keycode(k)
    return unless @map.member? kc
    entry = @map.delete kc
    keys = entry[2]
    keys.delete k
    @order.delete entry if keys.empty?
  end

  def add! action, help, *keys
    keys.each { |k| delete k }
    add action, help, *keys
  end

  def add_multi prompt, key
    kc = Keymap.keysym_to_keycode(key)
    if @map.member? kc
      action = @map[kc].first
      raise "existing action is not a keymap" unless action.is_a?(Keymap)
      yield action
    else
      submap = Keymap.new
      add submap, prompt, key
      yield submap
    end
  end

  def action_for kc
    action, help, keys = @map[kc]
    [action, help]
  end

  def has_key? k; @map[k] end

  def keysyms; @map.values.map { |action, help, keys| keys }.flatten; end

  def help_lines except_for={}, prefix=""
    lines = [] # :(
    @order.each do |action, help, keys|
      valid_keys = keys.select { |k| !except_for[k] }
      next if valid_keys.empty?
      case action
      when Symbol
        lines << [valid_keys.map { |k| prefix + Keymap.keysym_to_string(k) }.join(", "), help]
      when Keymap
        lines += action.help_lines({}, prefix + Keymap.keysym_to_string(keys.first))
      end
    end.compact
    lines
  end

  def help_text except_for={}
    lines = help_lines except_for
    llen = lines.max_of { |a, b| a.length }
    lines.map { |a, b| sprintf " %#{llen}s : %s", a, b }.join("\n")
  end

  def self.run_hook global_keymap
    modes = Hash[Mode.keymaps.map { |klass,keymap| [Mode.make_name(klass.name),klass] }]
    locals = {
      :modes => modes,
      :global_keymap => global_keymap,
    }
    HookManager.run 'keybindings', locals
  end
end

end
