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

  def mutex; @mutex ||= Mutex.new; end
  def sync &b; mutex.synchronize(&b); end

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

  module_function :rows, :cols, :nonblocking_getch, :mutex, :sync

  KEY_CANCEL = "\a"[0] # ctrl-g
end

module Redwood

class Buffer
  attr_reader :mode, :x, :y, :width, :height, :title
  bool_reader :dirty
  bool_accessor :force_to_top

  def initialize window, mode, width, height, opts={}
    @w = window
    @mode = mode
    @dirty = true
    @focus = false
    @title = opts[:title] || ""
    @force_to_top = opts[:force_to_top] || false
    @x, @y, @width, @height = 0, 0, width, height
  end

  def content_height; @height - 1; end
  def content_width; @width; end

  def resize rows, cols 
    return if cols == @width && rows == @height
    @width = cols
    @height = rows
    @dirty = true
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
    @minibuf_mutex = Mutex.new
    @textfields = {}
    @flash = nil
    @shelled = @asking = false

    self.class.i_am_the_instance self
  end

  def buffers; @name_map.to_a; end

  def focus_on buf
    raise ArgumentError, "buffer not on stack: #{buf.inspect}" unless @buffers.member? buf
    return if buf == @focus_buf 
    @focus_buf.blur if @focus_buf
    @focus_buf = buf
    @focus_buf.focus
  end

  def raise_to_front buf
    raise ArgumentError, "buffer not on stack: #{buf.inspect}" unless @buffers.member? buf

    @buffers.delete buf
    if @buffers.length > 0 && @buffers.last.force_to_top?
      @buffers.insert -2, buf
    else
      @buffers.push buf
      focus_on buf
    end
    @dirty = true
  end

  ## we reset force_to_top when rolling buffers. this is so that the
  ## human can actually still move buffers around, while still
  ## programmatically being able to pop stuff up in the middle of
  ## drawing a window without worrying about covering it up.
  ##
  ## if we ever start calling roll_buffers programmatically, we will
  ## have to change this. but it's not clear that we will ever actually
  ## do that.
  def roll_buffers
    @buffers.last.force_to_top = false
    raise_to_front @buffers.first
  end

  def roll_buffers_backwards
    return unless @buffers.length > 1
    @buffers.last.force_to_top = false
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
    return if @shelled

    Ncurses.sync do
      @dirty = true
      Ncurses.clear
      draw_screen :sync => false
    end
  end

  def handle_resize
    return if @shelled
    rows, cols = Ncurses.rows, Ncurses.cols
    @buffers.each { |b| b.resize rows - minibuf_lines, cols }
    completely_redraw_screen
    flash "Resized to #{rows}x#{cols}"
  end

  def draw_screen opts={}
    return if @shelled

    Ncurses.mutex.lock unless opts[:sync] == false

    ## disabling this for the time being, to help with debugging
    ## (currently we only have one buffer visible at a time).
    ## TODO: reenable this if we allow multiple buffers
    false && @buffers.inject(@dirty) do |dirty, buf|
      buf.resize Ncurses.rows - minibuf_lines, Ncurses.cols
      @dirty ? buf.draw : buf.redraw
    end

    ## quick hack
    if true
      buf = @buffers.last
      buf.resize Ncurses.rows - minibuf_lines, Ncurses.cols
      @dirty ? buf.draw : buf.redraw
    end

    draw_minibuf :sync => false unless opts[:skip_minibuf]
    @dirty = false
    Ncurses.doupdate
    Ncurses.refresh if opts[:refresh]
    Ncurses.mutex.unlock unless opts[:sync] == false
  end

  ## gets the mode from the block, which is only called if the buffer
  ## doesn't already exist. this is useful in the case that generating
  ## the mode is expensive, as it often is.
  def spawn_unless_exists title, opts={}
    if @name_map.member? title
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
      realtitle = "#{title} <#{num}>"
      num += 1
    end

    width = opts[:width] || Ncurses.cols
    height = opts[:height] || Ncurses.rows - 1

    ## since we are currently only doing multiple full-screen modes,
    ## use stdscr for each window. once we become more sophisticated,
    ## we may need to use a new Ncurses::WINDOW
    ##
    ## w = Ncurses::WINDOW.new(height, width, (opts[:top] || 0),
    ## (opts[:left] || 0))
    w = Ncurses.stdscr
    b = Buffer.new w, mode, width, height, :title => realtitle, :force_to_top => (opts[:force_to_top] || false)
    mode.buffer = b
    @name_map[realtitle] = b

    @buffers.unshift b
    if opts[:hidden]
      focus_on b unless @focus_buf
    else
      raise_to_front b
    end
    b
  end

  def kill_all_buffers_safely
    until @buffers.empty?
      ## inbox mode always claims it's unkillable. we'll ignore it.
      return false unless @buffers.first.mode.is_a?(InboxMode) || @buffers.first.mode.killable?
      kill_buffer @buffers.first
    end
    true
  end

  def kill_buffer_safely buf
    return false unless buf.mode.killable?
    kill_buffer buf
    true
  end

  def kill_all_buffers
    kill_buffer @buffers.first until @buffers.empty?
  end

  def kill_buffer buf
    raise ArgumentError, "buffer not on stack: #{buf.inspect}" unless @buffers.member? buf

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

  ## not really thread safe.
  def ask domain, question, default=nil
    raise "impossible!" if @asking

    @textfields[domain] ||= TextField.new Ncurses.stdscr, Ncurses.rows - 1, 0, Ncurses.cols
    tf = @textfields[domain]

    ## this goddamn ncurses form shit is a fucking 1970's
    ## nightmare. jesus christ. the exact sequence of ncurses events
    ## that needs to happen in order to display a form and have the
    ## entire screen not disappear and have the cursor in the right
    ## place is TOO FUCKING COMPLICATED.
    Ncurses.sync do
      tf.activate question, default
      @dirty = true
      draw_screen :skip_minibuf => true, :sync => false
    end

    ret = nil
    tf.position_cursor
    Ncurses.sync { Ncurses.refresh }

    @asking = true
    while tf.handle_input(Ncurses.nonblocking_getch); end
    @asking = false

    ret = tf.value
    Ncurses.sync { tf.deactivate }
    @dirty = true

    ret
  end

  ## some pretty lame code in here!
  def ask_getch question, accept=nil
    accept = accept.split(//).map { |x| x[0] } if accept

    flash question
    Ncurses.sync do
      Ncurses.curs_set 1
      Ncurses.move Ncurses.rows - 1, question.length + 1
      Ncurses.refresh
    end

    ret = nil
    done = false
    @shelled = true
    until done
      key = Ncurses.nonblocking_getch
      if key == Ncurses::KEY_CANCEL
        done = true
      elsif (accept && accept.member?(key)) || !accept
        ret = key
        done = true
      end
    end

    @shelled = false

    Ncurses.sync do
      Ncurses.curs_set 0
      erase_flash
      draw_screen :sync => false
      Ncurses.curs_set 0
    end

    ret
  end

  ## returns true (y), false (n), or nil (ctrl-g / cancel)
  def ask_yes_or_no question
    case(r = ask_getch question, "ynYN")
    when ?y, ?Y
      true
    when nil
      nil
    else
      false
    end
  end

  def minibuf_lines
    @minibuf_mutex.synchronize do
      [(@flash ? 1 : 0) + 
       (@asking ? 1 : 0) +
       @minibuf_stack.compact.size, 1].max
    end
  end
  
  def draw_minibuf opts={}
    m = nil
    @minibuf_mutex.synchronize do
      m = @minibuf_stack.compact
      m << @flash if @flash
      m << "" if m.empty?
    end

    Ncurses.mutex.lock unless opts[:sync] == false
    Ncurses.attrset Colormap.color_for(:none)
    adj = @asking ? 2 : 1
    m.each_with_index do |s, i|
      Ncurses.mvaddstr Ncurses.rows - i - adj, 0, s + (" " * [Ncurses.cols - s.length, 0].max)
    end
    Ncurses.refresh if opts[:refresh]
    Ncurses.mutex.unlock unless opts[:sync] == false
  end

  def say s, id=nil
    new_id = nil

    @minibuf_mutex.synchronize do
      new_id = id.nil?
      id ||= @minibuf_stack.length
      @minibuf_stack[id] = s
    end

    if new_id
      draw_screen :refresh => true
    else
      draw_minibuf :refresh => true
    end

    if block_given?
      begin
        yield id
      ensure
        clear id
      end
    end
    id
  end

  def erase_flash; @flash = nil; end

  def flash s
    @flash = s
    draw_screen :refresh => true
  end

  ## a little tricky because we can't just delete_at id because ids
  ## are relative (they're positions into the array).
  def clear id
    @minibuf_mutex.synchronize do
      @minibuf_stack[id] = nil
      if id == @minibuf_stack.length - 1
        id.downto(0) do |i|
          break if @minibuf_stack[i]
          @minibuf_stack.delete_at i
        end
      end
    end

    draw_screen :refresh => true
  end

  def shell_out command
    @shelled = true
    Ncurses.sync do
      Ncurses.endwin
      system command
      Ncurses.refresh
      Ncurses.curs_set 0
    end
    @shelled = false
  end
end
end
