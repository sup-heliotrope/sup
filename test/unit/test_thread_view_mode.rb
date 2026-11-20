require "dummy_buffer"
require "dummy_source"
require "test_helper"

require "sup"

module Redwood

class TestThreadViewMode < Minitest::Test
  def setup
    $config = {
      :indent_spaces => 2,
      :thread_by_subject => false,
    }
    @path = Dir.mktmpdir
    @out = File.open File::NULL, "w"
    @inp = File.open File::NULL, "r"
    @screen = Ncurses.newterm "dumb", @out, @inp
    BufferManager.init
    Redwood::start
    Logger.remove_sink $stderr
    Index.init File.join(@path, "xapian")
    Index.load
    @source = DummySource.new("sup-test://test_thread_view_mode")
    SourceManager.instance.instance_eval '@sources = {}'
    SourceManager.instance.add_source @source
  end

  def teardown
    ObjectSpace.each_object(Class).select {|a| a < Singleton}.each do |klass|
      klass.deinstantiate! unless klass == Logger
    end
    FileUtils.rm_r @path
    Ncurses.delscreen @screen
    @inp.close
    @out.close
    $config = nil
  end

  def populate_threadset
    PollManager.poll_from @source
    Index.save_index
    ts = ThreadSet.new Index.instance
    Index.instance.each_message { |m| ts.load_thread_for_message m }
    ts
  end

  def make_mode thread
    mode = ThreadViewMode.new thread
    mode.buffer = DummyBuffer.new 100, 24
    mode.send :regen_text
    mode
  end

  def test_attachment_filenames_escaping
    @source.messages = [ fixture_path("malicious-attachment-names.eml") ]
    ts = populate_threadset
    t = ts.threads.first
    mode = make_mode t
    mode.jump_to_message t.first

    ## Test saving all attachments to disk.
    destdir = File.join(@path, "saved")
    Dir.mkdir destdir
    stub(BufferManager.instance).ask(:filename, "Save all attachments to folder: ", "") { destdir }
    stub(BufferManager.instance).flash("Wrote 1 attachment to #{destdir}.")
    mode.save_all_to_disk
    expected_path = File.join destdir, "sup_.travis.yml"
    assert File.exist? expected_path
    assert_equal 260, File.size(expected_path)
  end
end

end
