require 'curses'

module Redwood

class TextField
  attr_reader :value

  def initialize window, y, x, width
    @w, @x, @y = window, x, y
    @width = width
    @i = nil
    @history = []
  end

  def activate question, default=nil
    @question = question
    @value = nil
    @field = Ncurses::Form.new_field 1, @width - question.length,
                                     @y, @x + question.length, 0, 0
    @form = Ncurses::Form.new_form [@field]

    @history[@i = @history.size] = default || ""
    Ncurses::Form.post_form @form
    @field.set_field_buffer 0, @history[@i]
  end

  def position_cursor
    @w.attrset Colormap.color_for(:none)
    @w.mvaddstr @y, 0, @question
    Ncurses.curs_set 1
    Ncurses::Form.form_driver @form, Ncurses::Form::REQ_END_FIELD
  end

  def deactivate
    @form.unpost_form
    @form.free_form
    @field.free_field
    Ncurses.curs_set 0
  end

  def handle_input c
    if c == 10 # Ncurses::KEY_ENTER
      Ncurses::Form.form_driver @form, Ncurses::Form::REQ_VALIDATION
      @value = @history[@i] = @field.field_buffer(0).gsub(/^\s+|\s+$/, "").gsub(/\s+/, " ")
      return false
    elsif c == Ncurses::KEY_CANCEL
      @history.delete_at @i
      @i = @history.empty? ? nil : (@i - 1) % @history.size 
      @value = nil
      return false
    end

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
        @history[@i] = @field.field_buffer(0)
        @i = (@i - 1) % @history.size
        @field.set_field_buffer 0, @history[@i]
      when Ncurses::KEY_DOWN
        @history[@i] = @field.field_buffer(0)
        @i = (@i + 1) % @history.size
        @field.set_field_buffer 0, @history[@i]
      else
        c
      end

    Ncurses::Form.form_driver @form, d
    Ncurses.refresh

    true
  end
end
end
