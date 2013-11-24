require 'ncursesw'
require 'sup/util'

if defined? Ncurses
module Ncurses

  ## Helper class for storing keycodes
  ## and multibyte characters.
  class CharCode < String

    # Empty singleton that
    # keeps GC from going crazy.
    class Empty < CharCode
      include Singleton

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

      def empty?    ; true  end   ## always true
      def present?  ; false end   ## always false
      def clear     ; self  end   ## always self
    end # CharCode::Empty

    ## Status code allows us to detect
    ## printable characters and control codes.
    attr_reader :status

    ## Reads character from user input.
    def self.nonblocking_getwch
      # If we get input while we're shelled, we'll ignore it for the
      # moment and use Ncurses.sync to wait until the shell_out is done.
      Redwood::BufferManager.shelled? ? Ncurses.sync { nil } : Ncurses.get_wch
    end

    ## Returns empty singleton.
    def self.empty
      Empty.instance
    end

    ## Creates new instance of CharCode
    ## that keeps a given keycode
    def self.keycode(c)
      new c, Ncurses::KEY_CODE_YES
    end

    ## Creates new instance of CharCode
    ## that keeps a printable character
    def self.character(c)
      new c
    end

    ## Tries to make external character right.
    def self.enc_char(c)
      begin
        character = c.chr($encoding)
      rescue RangeError, ArgumentError
        character = [c].pack('U')
        character.fix_encoding!
      end
    end

    ## Gets character from input.
    ## Pretends ctrl-c's are ctrl-g's.
    def self.get handle_interrupt=true
      begin
        status, code = nonblocking_getwch
        new enc_char(code), status
      rescue Interrupt => e
        raise e unless handle_interrupt
        keycode Ncurses::KEY_CANCEL
      end
    end

    def initialize(c = "", status = Ncurses::OK)
      @status = status
      c = "" if c.nil?
      return super("") if status == Ncurses::ERR
      c = self.class.enc_char(c) if c.is_a?(Fixnum)
      super c[0,1]
    end

    ## Proxy method for String's replace
    def replace(c)
      return self if c.object_id == object_id
      if c.is_a?(self.class)
        @status = c.status
        super(c)
      else
        @status = Ncurses::OK
        c = self.class.enc_char(c) if c.is_a?(Fixnum)
        super(c.to_s[0,1])
      end
    end

    def to_character    ; character? ? self : "<#{code}>"         end   ## Returns character or code as a string
    def to_keycode      ; keycode?   ? code : 0                   end   ## Returns keycode or 0 if it's not a keycode
    def code            ; ord                                     end   ## Returns decimal representation of a character
    def is_keycode?(c)  ; keycode?   &&  code == c                end   ## Tests if keycode matches
    def is_character?(c); character? &&  self == c                end   ## Tests if character matches
    def try_keycode     ; keycode?   ? code : nil                 end   ## Returns dec. code if keycode, nil otherwise
    def try_character   ; character? ? self : nil                 end   ## Returns character if character, nil otherwise
    def keycode         ; try_keycode                             end   ## Alias for try_keycode
    def character       ; try_character                           end   ## Alias for try_character
    def character?      ; @status == Ncurses::OK                  end   ## Returns true if character
    def character!      ; @status  = Ncurses::OK ; self           end   ## Sets character flag
    def keycode?        ; @status == Ncurses::KEY_CODE_YES        end   ## Returns true if keycode
    def keycode!        ; @status  = Ncurses::KEY_CODE_YES ; self end   ## Sets keycode flag
    def keycode=(c)     ; replace(c); keycode! ; self             end   ## Sets keycode    
    def present?        ; not empty?                              end   ## Proxy method
    def printable?      ; character?                              end   ## Alias for character?
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
      msg = "Your Ncursesw does not have a form_driver_w function (wide char aware), " \
            "non-ASCII chars may not work on your system."
      warn  msg
      print msg
      sleep 3
      Form.module_eval <<-FRM_DRV, __FILE__, __LINE__ + 1
        def form_driver_w form, status, c
          form_driver form, c
        end
        module_function :form_driver_w
      FRM_DRV
    end # if not defined? Form.form_driver_w
  end

  def mutex; @mutex ||= Mutex.new; end
  def sync &b; mutex.synchronize(&b); end

  module_function :rows, :cols, :curx, :mutex, :sync, :prepare_form_driver

  remove_const :KEY_ENTER
  remove_const :KEY_CANCEL

  KEY_ENTER = 10
  KEY_CANCEL = 7 # ctrl-g
  KEY_TAB = 9
end
end # if defined? Ncurses
