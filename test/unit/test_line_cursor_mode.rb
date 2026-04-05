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
    @lines = (0...40).map { |i| "line #{i}" }
    @load_more = Thread::Queue.new
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
    mode.buffer = Redwood::DummyBuffer.new 100, lines.length + 1
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
    (0...n).map { |i| @lines << "more line #{i}" }
  end

  def test_cursor_down
    mode = make_mode

    20.times do
      mode.handle_input Ncurses::CharCode.character('j')
    end
    assert_equal 20, mode.curpos
    assert_equal 0, mode.topline

    ## One past halfway, load_more callbacks are triggered.
    mode.handle_input Ncurses::CharCode.character('j')
    assert_equal 21, mode.curpos
    expect_load_more 40

    18.times do
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

    ## When the cursor is already at the top, it moves with the scroll.
    assert_equal 0, mode.curpos
    assert_equal 0, mode.topline
    mode.handle_input Ncurses::CharCode.character('J')
    assert_equal 1, mode.curpos
    assert_equal 1, mode.topline

    ## It always loads 10 more if we would scroll past the bottom.
    expect_load_more 10

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
  end

  def test_page_down
    mode = make_mode

    ## In theory, we should scroll a full page down. But because we always load
    ## exactly enough lines to fill one page, the first time we are off by one.
    mode.handle_input Ncurses::CharCode.keycode(Ncurses::KEY_NPAGE)
    assert_equal 0, mode.curpos
    assert_equal 39, mode.topline
    expect_load_more 40

    ## ThreadIndexMode#update does this, which I think is the only reason curpos
    ## does not end up pointing to an invisible line...
    mode.send :set_cursor_pos, 39
    assert_equal 39, mode.curpos
    assert_equal 39, mode.topline

    ## Now we have 80 lines but the top is at line 39, which makes the next
    ## page down behaviour even more awkward...
    assert_equal 80, mode.lines
    mode.handle_input Ncurses::CharCode.keycode(Ncurses::KEY_NPAGE)
    assert_equal 79, mode.curpos
    assert_equal 79, mode.topline
    assert_equal 80, mode.lines
    assert @load_more.empty?

    ## Page down does not trigger load_more callbacks, which is not very nice.
    mode.handle_input Ncurses::CharCode.keycode(Ncurses::KEY_NPAGE)
    mode.handle_input Ncurses::CharCode.keycode(Ncurses::KEY_NPAGE)
    mode.handle_input Ncurses::CharCode.keycode(Ncurses::KEY_NPAGE)
    assert_equal 80, mode.lines
    assert @load_more.empty?

    ## Sending cursor_down to ThreadIndexView when it's in this state *does*
    ## trigger load_more callbacks though. It doesn't happen in this test so
    ## it's probably a side effect of some interactions between the two classes
    ## like the #update method.
    mode.handle_input Ncurses::CharCode.character('j')
    #expect_load_more 40
    assert_equal 79, mode.curpos
    assert_equal 79, mode.topline
  end

  def test_page_down_when_fully_populated
    mode = make_mode
    (0...120).map { |i| @lines << "more line #{i}" }  # enough for 4 full pages

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
