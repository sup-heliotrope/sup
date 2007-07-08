require 'curses'

module Redwood

## a fully-functional text field supporting completions, expansions,
## history--everything!
##
## completion is done emacs-style, and mostly depends on outside
## support, as we merely signal the existence of a new set of
## completions to show (#new_completions?)  or that the current list
## of completions should be rolled if they're too large to fill the
## screen (#roll_completions?).
##
## in sup, completion support is implemented through BufferManager#ask
## and CompletionMode.
class TextField
  def initialize window, y, x, width
    @w, @x, @y = window, x, y
    @width = width
    @i = nil
    @history = []

    @completion_block = nil
    reset_completion_state
  end

  bool_reader :new_completions, :roll_completions
  attr_reader :completions

  ## when the user presses enter, we store the value in @value and
  ## clean up all the ncurses cruft. before @value is set, we can
  ## get the current value from ncurses.
  def value; @field ? get_cur_value : @value end

  def activate question, default=nil, &block
    @question = question
    @value = nil
    @completion_block = block
    @field = Ncurses::Form.new_field 1, @width - question.length,
                                     @y, @x + question.length, 0, 0
    @form = Ncurses::Form.new_form [@field]

    @history[@i = @history.size] = default || ""
    Ncurses::Form.post_form @form
    set_cur_value @history[@i]
  end

  def position_cursor
    @w.attrset Colormap.color_for(:none)
    @w.mvaddstr @y, 0, @question
    Ncurses.curs_set 1
    Ncurses::Form.form_driver @form, Ncurses::Form::REQ_END_FIELD
    Ncurses::Form.form_driver @form, Ncurses::Form::REQ_NEXT_CHAR if @history[@i] =~ / $/ # fucking RETARDED!!!!
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
      @value = @history[@i] = get_cur_value
      return false
    when Ncurses::KEY_CANCEL # cancel
      @history.delete_at @i
      @i = @history.empty? ? nil : (@i - 1) % @history.size 
      @value = nil
      return false
    when Ncurses::KEY_TAB # completion
      return true unless @completion_block
      if @completions.empty?
        v = get_cur_value
        c = @completion_block.call v
        if c.size > 0
          set_cur_value c.map { |full, short| full }.shared_prefix
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

    d =
      case c
      when Ncurses::KEY_LEFT
        Ncurses::Form::REQ_PREV_CHAR
      when Ncurses::KEY_RIGHT
        Ncurses::Form::REQ_NEXT_CHAR
      when Ncurses::KEY_BACKSPACE
        Ncurses::Form::REQ_DEL_PREV
      when ?\001
        Ncurses::Form::REQ_BEG_FIELD
      when ?\005
        Ncurses::Form::REQ_END_FIELD
      when Ncurses::KEY_UP
        @history[@i] = @field.field_buffer 0
        @i = (@i - 1) % @history.size
        set_cur_value @history[@i]
      when Ncurses::KEY_DOWN
        @history[@i] = @field.field_buffer 0
        @i = (@i + 1) % @history.size
        set_cur_value @history[@i]
      else
        c
      end

    Ncurses::Form.form_driver @form, d
    true
  end

private

  def reset_completion_state
    @completions = []
    @new_completions = @roll_completions = @clear_completions = false
  end

  ## ncurses inanity wrapper
  def get_cur_value
    Ncurses::Form.form_driver @form, Ncurses::Form::REQ_VALIDATION
    @field.field_buffer(0).gsub(/^\s+|\s+$/, "").gsub(/\s+/, " ")
  end
  
  ## ncurses inanity wrapper
  def set_cur_value v
    @field.set_field_buffer 0, v
    Ncurses::Form.form_driver @form, Ncurses::Form::REQ_END_FIELD
  end

end
end
