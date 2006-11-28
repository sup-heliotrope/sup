require "curses"

module Redwood

class Colormap
  @@instance = nil

  CURSES_COLORS = [Curses::COLOR_BLACK, Curses::COLOR_RED, Curses::COLOR_GREEN,
                   Curses::COLOR_YELLOW, Curses::COLOR_BLUE,
                   Curses::COLOR_MAGENTA, Curses::COLOR_CYAN,
                   Curses::COLOR_WHITE]
  NUM_COLORS = 15
  
  def initialize
    raise "only one instance can be created" if @@instance
    @@instance = self
    @entries = {}
    @color_pairs = {[Curses::COLOR_WHITE, Curses::COLOR_BLACK] => 0}
    @users = []
    @next_id = 0
    yield self if block_given?
    @entries[highlight_sym(:none)] = highlight_for(Curses::COLOR_WHITE,
                                                   Curses::COLOR_BLACK,
                                                   []) + [nil]
  end

  def add sym, fg, bg, *attrs
    raise ArgumentError, "color for #{sym} already defined" if
      @entries.member? sym
    raise ArgumentError, "color '#{fg}' unknown" unless CURSES_COLORS.include? fg
    raise ArgumentError, "color '#{bg}' unknown" unless CURSES_COLORS.include? bg

    @entries[sym] = [fg, bg, attrs, nil]
    @entries[highlight_sym(sym)] = highlight_for(fg, bg, attrs) + [nil]
  end

  def highlight_sym sym
    "#{sym}_highlight".intern
  end

  def highlight_for fg, bg, attrs
    hfg =
      case fg
      when Curses::COLOR_BLUE
        Curses::COLOR_WHITE
      when Curses::COLOR_YELLOW, Curses::COLOR_GREEN
        fg
      else
        Curses::COLOR_BLACK
      end

    hbg = 
      case bg
      when Curses::COLOR_CYAN
        Curses::COLOR_YELLOW
      else
        Curses::COLOR_CYAN
      end

    attrs =
      if fg == Curses::COLOR_WHITE && attrs.include?(Curses::A_BOLD)
        [Curses::A_BOLD]
      else
        case hfg
        when Curses::COLOR_BLACK
          []
        else
          [Curses::A_BOLD]
        end
      end
    [hfg, hbg, attrs]
  end

  def color_for sym, highlight=false
    sym = highlight_sym(sym) if highlight
    return Curses::COLOR_BLACK if sym == :none
    raise ArgumentError, "undefined color #{sym}" unless @entries.member? sym

    ## if this color is cached, return it
    fg, bg, attrs, color = @entries[sym]
    return color if color

    if(cp = @color_pairs[[fg, bg]])
      ## nothing
    else ## need to get a new colorpair
      @next_id = (@next_id + 1) % NUM_COLORS
      @next_id += 1 if @next_id == 0 # 0 is always white on black
      id = @next_id
      Redwood::log "colormap: for color #{sym}, using id #{id} -> #{fg}, #{bg}"
      Curses.init_pair id, fg, bg or raise ArgumentError,
        "couldn't initialize curses color pair #{fg}, #{bg} (key #{id})"

      cp = @color_pairs[[fg, bg]] = Curses.color_pair(id)
      ## delete the old mapping, if it exists
      if @users[cp]
        @users[cp].each do |usym|
          Redwood::log "dropping color #{usym} (#{id})"
          @entries[usym][3] = nil
        end
        @users[cp] = []
      end
    end

    ## by now we have a color pair
    color = attrs.inject(cp) { |color, attr| color | attr }
    @entries[sym][3] = color # fill the cache
    (@users[cp] ||= []) << sym # record entry as a user of that color pair
    color
  end

  def self.instance; @@instance; end
  def self.method_missing meth, *a
    Colorcolors.new unless @@instance
    @@instance.send meth, *a
  end
end

end
