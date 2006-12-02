require 'thread'

module Ncurses
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

  ## aaahhh, user input. who would have though that such a simple
  ## idea would be SO FUCKING COMPLICATED?! because apparently
  ## Ncurses.getch (and Curses.getch), even in cbreak mode, BLOCKS
  ## ALL THREAD ACTIVITY. as in, no threads anywhere will run while
  ## it's waiting for input. ok, fine, so we wrap it in a select. Of
  ## course we also rely on Ncurses.getch to tell us when an xterm
  ## resize has occurred, which select won't catch, so we won't
  ## resize outselves after a sigwinch until the user hits a key.
  ## and installing our own sigwinch handler means that the screen
  ## size returned by getmaxyx() DOESN'T UPDATE! and Kernel#trap
  ## RETURNS NIL as the previous handler! 
  ##
  ## so basically, resizing with multi-threaded ruby Ncurses
  ## applications will always be broken.
  ##
  ## i've coined a new word for this: lametarded.
  def nonblocking_getch
    if IO.select([$stdin], nil, nil, nil)
      Ncurses.getch
    else
      nil
    end
  end

  module_function :rows, :cols, :nonblocking_getch

  KEY_CANCEL = "\a"[0] # ctrl-g
end

module Redwood

class Buffer
  attr_reader :mode, :x, :y, :width, :height, :title
  bool_reader :dirty

  def initialize window, mode, width, height, opts={}
    @w = window
    @mode = mode
    @dirty = true
    @focus = false
    @title = opts[:title] || ""
    @x, @y, @width, @height = 0, 0, width, height
  end

  def content_height; @height - 1; end
  def content_width; @width; end

  def resize rows, cols
    @width = cols
    @height = rows
    mode.resize rows, cols
  end

  def redraw
    draw if @dirty
    draw_status
    commit
  end
  def mark_dirty; @dirty = true; end

  def commit
    @dirty = false
    @w.noutrefresh
  end

  def draw
    @mode.draw
    draw_status
    commit
  end

  ## s nil means a blank line!
  def write y, x, s, opts={}
    return if x >= @width || y >= @height

    @w.attrset Colormap.color_for(opts[:color] || :none, opts[:highlight])
    s ||= ""
    maxl = @width - x
    @w.mvaddstr y, x, s[0 ... maxl]
    unless s.length >= maxl || opts[:no_fill]
      @w.mvaddstr(y, x + s.length, " " * (maxl - s.length))
    end
  end

  def clear
    @w.clear
  end

  def draw_status
    write @height - 1, 0, " [#{mode.name}] #{title}   #{mode.status}",
      :color => :status_color
  end

  def focus
    @focus = true
    @dirty = true
    @mode.focus
  end

  def blur
    @focus = false
    @dirty = true
    @mode.blur
  end
end

class BufferManager
  include Singleton

  attr_reader :focus_buf

  def initialize
    @name_map = {}
    @buffers = []
    @focus_buf = nil
    @dirty = true
    @minibuf_stack = []
    @textfields = {}
    @flash = nil
    @freeze = false

    self.class.i_am_the_instance self
  end

  def buffers; @name_map.to_a; end

  def focus_on buf
    raise ArgumentError, "buffer not on stack: #{buf.inspect}" unless
      @buffers.member? buf
    return if buf == @focus_buf 
    @focus_buf.blur if @focus_buf
    @focus_buf = buf
    @focus_buf.focus
  end

  def raise_to_front buf
    raise ArgumentError, "buffer not on stack: #{buf.inspect}" unless
      @buffers.member? buf
    @buffers.delete buf
    @buffers.push buf
    focus_on buf
    @dirty = true
  end

  def roll_buffers
    raise_to_front @buffers.first
  end

  def roll_buffers_backwards
    return unless @buffers.length > 1
    raise_to_front @buffers[@buffers.length - 2]
  end

  def handle_input c
    @focus_buf && @focus_buf.mode.handle_input(c)
  end

  def exists? n; @name_map.member? n; end
  def [] n; @name_map[n]; end
  def []= n, b
    raise ArgumentError, "duplicate buffer name" if b && @name_map.member?(n)
    @name_map[n] = b
  end

  def completely_redraw_screen
    return if @freeze
    Ncurses.clear
    @dirty = true
    draw_screen
  end

  def handle_resize
    return if @freeze
    rows, cols = Ncurses.rows, Ncurses.cols
    @buffers.each { |b| b.resize rows - 1, cols }
    completely_redraw_screen
    flash "resized to #{rows}x#{cols}"
  end

  def draw_screen skip_minibuf=false
    return if @freeze

    ## disabling this for the time being, to help with debugging
    ## (currently we only have one buffer visible at a time).
    ## TODO: reenable this if we allow multiple buffers
    false && @buffers.inject(@dirty) do |dirty, buf|
      dirty ? buf.draw : buf.redraw
      dirty || buf.dirty?
    end
    ## quick hack
    true && (@dirty ? @buffers.last.draw : @buffers.last.redraw)
    
    draw_minibuf unless skip_minibuf
    @dirty = false
    Ncurses.doupdate
  end

  ## gets the mode from the block, which is only called if the buffer
  ## doesn't already exist. this is useful in the case that generating
  ## the mode is expensive, as it often is.
  def spawn_unless_exists title, opts={}
    if @name_map.member? title
      Redwood::log "buffer '#{title}' already exists, raising to front"
      raise_to_front @name_map[title] unless opts[:hidden]
    else
      mode = yield
      spawn title, mode, opts
    end
    @name_map[title]
  end

  def spawn title, mode, opts={}
    realtitle = title
    num = 2
    while @name_map.member? realtitle
      realtitle = "#{title} #{num}"
      num += 1
    end

    Redwood::log "spawning buffer \"#{realtitle}\""
    width = opts[:width] || Ncurses.cols
    height = opts[:height] || Ncurses.rows - 1

    ## since we are currently only doing multiple full-screen modes,
    ## use stdscr for each window. once we become more sophisticated,
    ## we may need to use a new Ncurses::WINDOW
    ##
    ## w = Ncurses::WINDOW.new(height, width, (opts[:top] || 0),
    ## (opts[:left] || 0))
    w = Ncurses.stdscr
    raise "nil window" unless w
    
    b = Buffer.new w, mode, width, height, :title => realtitle
    mode.buffer = b
    @name_map[realtitle] = b
    if opts[:hidden]
      @buffers.unshift b
      focus_on b unless @focus_buf
    else
      @buffers.push b
      raise_to_front b
    end
    b
  end

  def kill_all_buffers
    kill_buffer @buffers.first until @buffers.empty?
  end

  def kill_buffer buf
    raise ArgumentError, "buffer not on stack: #{buf.inspect}" unless @buffers.member? buf
    Redwood::log "killing buffer \"#{buf.title}\""

    buf.mode.cleanup
    @buffers.delete buf
    @name_map.delete buf.title
    @focus_buf = nil if @focus_buf == buf
    if @buffers.empty?
      ## TODO: something intelligent here
      ## for now I will simply prohibit killing the inbox buffer.
    else
      raise_to_front @buffers.last
    end
  end

  def ask domain, question, default=nil
    @textfields[domain] ||= TextField.new Ncurses.stdscr, Ncurses.rows - 1, 0,
                            Ncurses.cols
    tf = @textfields[domain]

    ## this goddamn ncurses form shit is a fucking 1970's
    ## nightmare. jesus christ. the exact sequence of ncurses events
    ## that needs to happen in order to display a form and have the
    ## entire screen not disappear and have the cursor in the right
    ## place is TOO FUCKING COMPLICATED.
    tf.activate question, default
    @dirty = true
    draw_screen true

    ret = nil
    @freeze = true
    tf.position_cursor
    Ncurses.refresh
    while tf.handle_input(Ncurses.nonblocking_getch); end
    @freeze = false

    ret = tf.value
    tf.deactivate
    @dirty = true

    ret
  end

  ## some pretty lame code in here!
  def ask_getch question, accept=nil
    accept = accept.split(//).map { |x| x[0] } if accept

    flash question
    Ncurses.curs_set 1
    Ncurses.move Ncurses.rows - 1, question.length + 1
    Ncurses.refresh

    ret = nil
    done = false
    @freeze = true
    until done
      key = Ncurses.nonblocking_getch
      if key == Ncurses::KEY_CANCEL
        done = true
      elsif (accept && accept.member?(key)) || !accept
        ret = key
        done = true
      end
    end
    @freeze = false
    Ncurses.curs_set 0
    erase_flash
    draw_screen
    Ncurses.curs_set 0

    ret
  end

  def ask_yes_or_no question
    [?y, ?Y].member? ask_getch(question, "ynYN")
  end

  def draw_minibuf
    s = @flash || @minibuf_stack.reverse.find { |x| x } || ""

    Ncurses.attrset Colormap.color_for(:none)
    Ncurses.mvaddstr Ncurses.rows - 1, 0, s + (" " * [Ncurses.cols - s.length,
                                                      0].max)
  end

  def say s, id=nil
    id ||= @minibuf_stack.length
    @minibuf_stack[id] = s
    unless @freeze
      draw_screen
      Ncurses.refresh
    end
    id
  end

  def erase_flash; @flash = nil; end

  def flash s
    @flash = s
    unless @freeze
      draw_screen
      Ncurses.refresh
    end
  end

  def clear id
    @minibuf_stack[id] = nil
    if id == @minibuf_stack.length - 1
      id.downto(0) do |i|
        break unless @minibuf_stack[i].nil?
        @minibuf_stack.delete_at i
      end
    end
    unless @freeze
      draw_screen
      Ncurses.refresh
    end
  end

  def shell_out command
    @freeze = true
    Ncurses.endwin
    system command
    Ncurses.refresh
    Ncurses.curs_set 0
    @freeze = false
  end
end
end
