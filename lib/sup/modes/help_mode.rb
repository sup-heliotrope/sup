module Redwood

class HelpMode < TextMode
  def initialize mode, global_keymap
    title = "Help for #{mode.name}"
    super <<EOS
#{title}
#{'=' * title.length}

#{mode.help_text}
Global keybindings
------------------
#{global_keymap.help_text}
EOS
  end
end

end

