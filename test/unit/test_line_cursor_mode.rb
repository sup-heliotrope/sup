require "test_helper"
require "dummy_buffer"

require "sup"

class TestLineCursorMode < Minitest::Test
  def setup
    $config = {
      :load_more_threads_hysteresis => 0,
      :load_more_threads_when_scrolling => true,
      :continuous_scroll => false,
    }
    Redwood::BufferManager.init
    @modes_to_cleanup = []
    @lines = []
    @load_more = Thread::Queue.new
    @buffer_height = 41  # 1 for status line, 40 usable lines
  end

  def teardown
    @modes_to_cleanup.each { |mode| mode.cleanup }
    Redwood::BufferManager.deinstantiate!
    $config = nil
  end

  def make_mode
    mode = Redwood::LineCursorMode.new
    @modes_to_cleanup << mode
    lines = @lines
    mode.define_singleton_method(:lines) { lines.length }
    mode.define_singleton_method(:[]) { |i| lines[i] }
    mode.send(:to_load_more) { |n| @load_more << n }
    mode.buffer = Redwood::DummyBuffer.new 100, @buffer_height
    mode.spawned
    mode.draw
    mode
  end

  def expect_load_more n
    begin
      requested = @load_more.pop :timeout => 0.1
    rescue ThreadError
      ## Ruby < 3.2 does not obey the timeout for Queue#pop
      sleep 0.1
      requested = @load_more.pop true
    end
    refute_nil requested, "Expected load_more callbacks to fire"
    assert_equal n, requested
    (0...n).map { |i| @lines << "line #{i}" }
  end

  def test_cursor_down
    mode = make_mode
    expect_load_more 41
    mode.draw  # curpos gets messed up without this call, why?

    21.times do
      mode.handle_input Ncurses::CharCode.character('j')
    end
    assert_equal 21, mode.curpos
    assert_equal 0, mode.topline

    ## Two past halfway, load_more callbacks are triggered.
    mode.handle_input Ncurses::CharCode.character('j')
    assert_equal 22, mode.curpos
    expect_load_more 40

    17.times do
      mode.handle_input Ncurses::CharCode.character('j')
    end
    assert_equal 39, mode.curpos
    assert_equal 0, mode.topline

    ## From the bottom line, it wraps back to the top of the next page.
    mode.handle_input Ncurses::CharCode.character('j')
    assert_equal 40, mode.curpos
    assert_equal 40, mode.topline
  end

  def test_scroll_down
    mode = make_mode
    expect_load_more 41

    ## When the cursor is already at the top, it moves with the scroll.
    assert_equal 0, mode.curpos
    assert_equal 0, mode.topline
    mode.handle_input Ncurses::CharCode.character('J')
    assert_equal 1, mode.curpos
    assert_equal 1, mode.topline

    3.times do
      mode.handle_input Ncurses::CharCode.character('j')
    end
    assert_equal 4, mode.curpos
    assert_equal 1, mode.topline

    ## When the cursor is not at the top, it keeps its place and the
    ## buffer scrolls underneath it.
    mode.handle_input Ncurses::CharCode.character('J')
    assert_equal 4, mode.curpos
    assert_equal 2, mode.topline

    ## It always loads 10 more if we would scroll past the bottom.
    expect_load_more 10
  end

  def test_page_down
    mode = make_mode
    expect_load_more 41

    mode.handle_input Ncurses::CharCode.keycode(Ncurses::KEY_NPAGE)
    assert_equal 40, mode.curpos
    assert_equal 40, mode.topline
    expect_load_more 40

    mode.handle_input Ncurses::CharCode.keycode(Ncurses::KEY_NPAGE)
    assert_equal 80, mode.curpos
    assert_equal 80, mode.topline
    assert_equal 81, mode.lines
    expect_load_more 40
  end

  def test_page_down_when_fully_populated
    mode = make_mode
    expect_load_more 41
    (0...119).map { |i| @lines << "more line #{i}" }  # enough for 4 full pages

    mode.handle_input Ncurses::CharCode.keycode(Ncurses::KEY_NPAGE)
    assert_equal 40, mode.curpos
    assert_equal 40, mode.topline

    ## Relative cursor position is preserved when paging down.
    3.times do
      mode.handle_input Ncurses::CharCode.character('j')
    end
    assert_equal 43, mode.curpos
    assert_equal 40, mode.topline
    mode.handle_input Ncurses::CharCode.keycode(Ncurses::KEY_NPAGE)
    assert_equal 83, mode.curpos
    assert_equal 80, mode.topline
  end
end
