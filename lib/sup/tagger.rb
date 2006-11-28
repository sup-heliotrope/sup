module Redwood

class Tagger
  def initialize mode
    @mode = mode
    @tagged = {}
  end

  def tagged? o; @tagged[o]; end
  def toggle_tag_for o; @tagged[o] = !@tagged[o]; end
  def drop_all_tags; @tagged.clear; end
  def drop_tag_for o; @tagged.delete o; end

  def apply_to_tagged
    num_tagged = @tagged.map { |t| t ? 1 : 0 }.sum
    if num_tagged == 0
      BufferManager.flash "No tagged messages!"
      return
    end

    noun = num_tagged == 1 ? "message" : "messages"
    c = BufferManager.ask_getch "apply to #{num_tagged} tagged #{noun}:"
    return if c.nil? # user cancelled

    if(action = @mode.resolve_input c)
      tagged_sym = "multi_#{action}".intern
      if @mode.respond_to? tagged_sym
        targets = @tagged.select_by_value
        @mode.send tagged_sym, targets
      else
        BufferManager.flash "That command cannot be applied to multiple messages."
      end
    else
      BufferManager.flash "Unknown command #{c.to_character}."
    end
  end

end

end
