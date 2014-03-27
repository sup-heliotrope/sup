require 'ncursesw'
require 'sup/util'

if defined? Ncurses
module Ncurses

  ## Helper class for storing keycodes
  ## and multibyte characters.
  class CharCode < String
    ## Status code allows us to detect
    ## printable characters and control codes.
    attr_reader :status

    ## Reads character from user input.
    def self.nonblocking_getwch
      # If we get input while we're shelled, we'll ignore it for the
      # moment and use Ncurses.sync to wait until the shell_out is done.
      begin
        s, c = Redwood::BufferManager.shelled? ? Ncurses.sync { nil } : Ncurses.get_wch
        break if s != Ncurses::ERR
      end until IO.select([$stdin], nil, nil, 2)
      [s, c]
    end

    ## Returns empty singleton.
    def self.empty
      Empty.instance
    end

    ## Creates new instance of CharCode
    ## that keeps a given keycode.
    def self.keycode(c)
      generate c, Ncurses::KEY_CODE_YES
    end

    ## Creates new instance of CharCode
    ## that keeps a printable character.
    def self.character(c)
      generate c, Ncurses::OK
    end

    ## Generates new object like new
    ## but for empty or erroneous objects
    ## it returns empty singleton.
    def self.generate(c = nil, status = Ncurses::OK)
      if status == Ncurses::ERR || c.nil? || c === Ncurses::ERR
        empty
      else
        new(c, status)
      end
    end

    ## Gets character from input.
    ## Pretends ctrl-c's are ctrl-g's.
    def self.get handle_interrupt=true
      begin
        status, code = nonblocking_getwch
        generate code, status
      rescue Interrupt => e
        raise e unless handle_interrupt
        keycode Ncurses::KEY_CANCEL
      end
    end

    ## Enables dumb mode for any new instance.
    def self.dumb!
      @dumb = true
    end

    ## Asks if dumb mode was set
    def self.dumb?
      defined?(@dumb) && @dumb
    end

    def initialize(c = "", status = Ncurses::OK)
      @status = status
      c = "" if c.nil?
      return super("") if status == Ncurses::ERR
      c = enc_char(c) if c.is_a?(Fixnum)
      super c.length > 1 ? c[0,1] : c
    end

    ## Proxy method for String's replace
    def replace(c)
      return self if c.object_id == object_id
      if c.is_a?(self.class)
        @status = c.status
        super(c)
      else
        @status = Ncurses::OK
        c = "" if c.nil?
        c = enc_char(c) if c.is_a?(Fixnum)
        super c.length > 1 ? c[0,1] : c
      end
    end

    def to_character    ; character? ? self : "<#{code}>"           end  ## Returns character or code as a string
    def to_keycode      ; keycode?   ? code : Ncurses::ERR          end  ## Returns keycode or ERR if it's not a keycode
    def to_sequence     ; bytes.to_a                                end  ## Returns unpacked sequence of bytes for a character
    def code            ; ord                                       end  ## Returns decimal representation of a character
    def is_keycode?(c)  ; keycode?   &&  code == c                  end  ## Tests if keycode matches
    def is_character?(c); character? &&  self == c                  end  ## Tests if character matches
    def try_keycode     ; keycode?   ? code : nil                   end  ## Returns dec. code if keycode, nil otherwise
    def try_character   ; character? ? self : nil                   end  ## Returns character if character, nil otherwise
    def keycode         ; try_keycode                               end  ## Alias for try_keycode
    def character       ; try_character                             end  ## Alias for try_character
    def character?      ; dumb? || @status == Ncurses::OK           end  ## Returns true if character
    def character!      ; @status  = Ncurses::OK ; self             end  ## Sets character flag
    def keycode?        ; dumb? || @status == Ncurses::KEY_CODE_YES end  ## Returns true if keycode
    def keycode!        ; @status  = Ncurses::KEY_CODE_YES ; self   end  ## Sets keycode flag
    def keycode=(c)     ; replace(c); keycode! ; self               end  ## Sets keycode    
    def present?        ; not empty?                                end  ## Proxy method
    def printable?      ; character?                                end  ## Alias for character?
    def dumb?           ; self.class.dumb?                          end  ## True if we cannot distinguish keycodes from characters

    # Empty singleton that
    # keeps GC from going crazy.
    class Empty < CharCode
      include Redwood::Singleton

      ## Wrap methods that may change us
      ## and generate new object instead.
      [ :"[]=", :"<<", :replace, :insert, :prepend, :append, :concat, :force_encoding, :setbyte ].
      select{ |m| public_method_defined?(m) }.
      concat(public_instance_methods.grep(/!\z/)).
      each do |m|
        class_eval <<-EVAL
          def #{m}(*args)
            CharCode.new.#{m}(*args)
          end
        EVAL
      end

      ## proxy with class-level instance variable delegation
      def self.dumb?
        superclass.dumb? or !!@dumb
      end

      def self.empty
        instance
      end

      def initialize
        super("", Ncurses::ERR)
      end

      def empty?    ; true  end   ## always true
      def present?  ; false end   ## always false
      def clear     ; self  end   ## always self

      self
    end.init # CharCode::Empty

    private

    ## Tries to make external character right.
    def enc_char(c)
      begin
        character = c.chr($encoding)
      rescue RangeError, ArgumentError
        begin
          character = [c].pack('U')
        rescue RangeError
          begin
            character = c.chr
          rescue
            begin
              character = [c].pack('C')
            rescue
              character = ""
              @status = Ncurses::ERR
            end
          end
        end
        character.fix_encoding!
      end
    end
  end # class CharCode

  def rows
    lame, lamer = [], []
    stdscr.getmaxyx lame, lamer
    lame.first
  end

  def cols
    lame, lamer = [], []
    stdscr.getmaxyx lame, lamer
    lamer.first
  end

  def curx
    lame, lamer = [], []
    stdscr.getyx lame, lamer
    lamer.first
  end

  ## Create replacement wrapper for form_driver_w (), which is not (yet) a standard
  ## function in ncurses. Some systems (Mac OS X) does not have a working
  ## form_driver that accepts wide chars. We are just falling back to form_driver, expect problems.
  def prepare_form_driver
    if not defined? Form.form_driver_w
      warn "Your Ncursesw does not have a form_driver_w function (wide char aware), " \
           "non-ASCII chars may not work on your system."
      Form.module_eval <<-FRM_DRV, __FILE__, __LINE__ + 1
        def form_driver_w form, status, c
          form_driver form, c
        end
        module_function :form_driver_w
        module DriverHelpers
          def form_driver c
            if !c.dumb? && c.printable?
              c.each_byte do |code|
                Ncurses::Form.form_driver @form, code
              end
            else
              Ncurses::Form.form_driver @form, c.code
            end
          end
        end
      FRM_DRV
    end # if not defined? Form.form_driver_w
    if not defined? Ncurses.get_wch
      warn "Your Ncursesw does not have a get_wch function (wide char aware), " \
           "non-ASCII chars may not work on your system."
      Ncurses.module_eval <<-GET_WCH, __FILE__, __LINE__ + 1
        def get_wch
          c = getch
          c == Ncurses::ERR ? [c, 0] : [Ncurses::OK, c]
        end
        module_function :get_wch
      GET_WCH
      CharCode.dumb!
    end # if not defined? Ncurses.get_wch
  end

  def mutex; @mutex ||= Mutex.new; end
  def sync &b; mutex.synchronize(&b); end

  module_function :rows, :cols, :curx, :mutex, :sync, :prepare_form_driver

  remove_const :KEY_ENTER
  remove_const :KEY_CANCEL

  KEY_ENTER = 10
  KEY_CANCEL = 7 # ctrl-g
  KEY_TAB = 9

  module Form
    ## This module contains helpers that ease
    ## using form_driver_ methods when @form is present.
    module DriverHelpers
      private

      ## Ncurses::Form.form_driver_w wrapper for keycodes and control characters.
      def form_driver_key c
        form_driver CharCode.keycode(c)
      end

      ## Ncurses::Form.form_driver_w wrapper for printable characters.
      def form_driver_char c
        form_driver CharCode.character(c)
        #c.is_a?(Fixnum) ? c : c.ord
      end

      ## Ncurses::Form.form_driver_w wrapper for charcodes.
      def form_driver c
        Ncurses::Form.form_driver_w @form, c.status, c.code
      end
    end # module DriverHelpers
  end # module Form

end # module Ncurses
end # if defined? Ncurses
