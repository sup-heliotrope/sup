module Redwood

class HelpMode < TextMode
  def initialize mode, global_keymap
    title = "#{I18n['help.help_for']} #{mode.name}"
    super <<EOS
#{title}
#{'=' * title.length}

#{mode.help_text}
#{I18n['help.global_keymap.headline']}
------------------
#{global_keymap.help_text}
EOS
  end
end

end

