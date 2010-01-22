module Redwood

## a fully-functional text field supporting completions, expansions,
## history--everything!
## 
## writing this fucking sucked. if you thought ncurses was some 1970s
## before-people-knew-how-to-program bullshit, wait till you see
## ncurses forms.
##
## completion comments: completion is done emacs-style, and mostly
## depends on outside support, as we merely signal the existence of a
## new set of completions to show (#new_completions?)  or that the
## current list of completions should be rolled if they're too large
## to fill the screen (#roll_completions?).
##
## in sup, completion support is implemented through BufferManager#ask
## and CompletionMode.
class TextField
  def initialize
    @i = nil
    @history = []

    @completion_block = nil
    reset_completion_state
  end

  bool_reader :new_completions, :roll_completions
  attr_reader :completions

  def value; @value || get_cursed_value end

  def activate window, y, x, width, question, default=nil, &block
    @w, @y, @x, @width = window, y, x, width
    @question = question
    @completion_block = block
    @field = Ncurses::Form.new_field 1, @width - question.length, @y, @x + question.length, 0, 0
    @field.opts_off Ncurses::Form::O_STATIC
    @field.opts_off Ncurses::Form::O_BLANK
    @form = Ncurses::Form.new_form [@field]
    @value = default || ''
    Ncurses::Form.post_form @form
    set_cursed_value @value
  end

  def position_cursor
    @w.attrset Colormap.color_for(:none)
    @w.mvaddstr @y, 0, @question
    Ncurses.curs_set 1
    Ncurses::Form.form_driver @form, Ncurses::Form::REQ_END_FIELD
    Ncurses::Form.form_driver @form, Ncurses::Form::REQ_NEXT_CHAR if @value && @value =~ / $/ # fucking RETARDED
  end

  def deactivate
    reset_completion_state
    @form.unpost_form
    @form.free_form
    @field.free_field
    @field = nil
    Ncurses.curs_set 0
  end

  def handle_input c
    ## short-circuit exit paths
    case c
    when Ncurses::KEY_ENTER # submit!
      @value = get_cursed_value
      @history.push @value unless @value =~ /^\s*$/
      return false
    when Ncurses::KEY_CANCEL # cancel
      @value = nil
      return false
    when Ncurses::KEY_TAB # completion
      return true unless @completion_block
      if @completions.empty?
        v = get_cursed_value
        c = @completion_block.call v
        if c.size > 0
          @value = c.map { |full, short| full }.shared_prefix(true)
          set_cursed_value @value
          position_cursor
        end
        if c.size > 1
          @completions = c
          @new_completions = true
          @roll_completions = false
        end
      else
        @new_completions = false
        @roll_completions = true
      end
      return true
    end

    reset_completion_state
    @value = nil

    d =
      case c
      when Ncurses::KEY_LEFT
        Ncurses::Form::REQ_PREV_CHAR
      when Ncurses::KEY_RIGHT
        Ncurses::Form::REQ_NEXT_CHAR
      when Ncurses::KEY_DC
        Ncurses::Form::REQ_DEL_CHAR
      when Ncurses::KEY_BACKSPACE, 127 # 127 is also a backspace keysym
        Ncurses::Form::REQ_DEL_PREV
      when ?\C-a
        nop
        Ncurses::Form::REQ_BEG_FIELD
      when ?\C-e
        Ncurses::Form::REQ_END_FIELD
      when ?\C-k
        Ncurses::Form::REQ_CLR_EOF
      when ?\C-u
        set_cursed_value cursed_value_after_point
        Ncurses::Form.form_driver @form, Ncurses::Form::REQ_END_FIELD
        nop
        Ncurses::Form::REQ_BEG_FIELD
      when ?\C-w
        Ncurses::Form.form_driver @form, Ncurses::Form::REQ_PREV_CHAR
        Ncurses::Form.form_driver @form, Ncurses::Form::REQ_DEL_WORD
      when Ncurses::KEY_UP, Ncurses::KEY_DOWN
        unless @history.empty?
          value = get_cursed_value
          @i ||= @history.size
          #debug "history before #{@history.inspect}"
          @history[@i] = value #unless value =~ /^\s*$/
          @i = (@i + (c == Ncurses::KEY_UP ? -1 : 1)) % @history.size
          @value = @history[@i]
          #debug "history after #{@history.inspect}"
          set_cursed_value @value
          Ncurses::Form::REQ_END_FIELD
        end
      else
        c
      end

    Ncurses::Form.form_driver @form, d if d
    true
  end

private

  def reset_completion_state
    @completions = []
    @new_completions = @roll_completions = @clear_completions = false
  end

  ## ncurses inanity wrapper
  ##
  ## DO NOT READ THIS CODE. YOU WILL GO MAD.
  def get_cursed_value
    return nil unless @field

    x = Ncurses.curx
    Ncurses::Form.form_driver @form, Ncurses::Form::REQ_VALIDATION
    v = @field.field_buffer(0).gsub(/^\s+|\s+$/, "")

    ## cursor <= end of text
    if x - @question.length - v.length <= 0
      v
    else # trailing spaces
      v + (" " * (x - @question.length - v.length))
    end
  end

  def set_cursed_value v
    @field.set_field_buffer 0, v
  end

  def cursed_value_after_point
    point = Ncurses.curx - @question.length
    get_cursed_value[point..-1]
  end

  ## this is almost certainly unnecessary, but it's the only way
  ## i could get ncurses to remember my form's value
  def nop
    Ncurses::Form.form_driver @form, " "[0]
    Ncurses::Form.form_driver @form, Ncurses::Form::REQ_DEL_PREV
  end
end
end
