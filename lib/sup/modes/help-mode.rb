module Redwood

class HelpMode < TextMode
  include M17n

  def initialize mode, global_keymap
    title = "#{m('help.help_for')} #{mode.name}"
    super <<EOS
#{title}
#{'=' * title.length}

#{mode.help_text}
#{m('help.global_keymap.headline')}
------------------
#{global_keymap.help_text}
EOS
  end
end

end

