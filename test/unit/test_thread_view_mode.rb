require "test_helper"
require "dummy_buffer"
require "dummy_source"

require "sup"

module Redwood

class TestThreadViewMode < Minitest::Test
  def setup
    $config = {
      :indent_spaces => 2,
      :thread_by_subject => false,
      :stem_language => "english",
      :default_attachment_save_dir => "",
    }
    @path = Dir.mktmpdir
    @out = File.open File::NULL, "w"
    @inp = File.open File::NULL, "r"
    @screen = Ncurses.newterm "dumb", @out, @inp
    BufferManager.init
    Logger.remove_sink $stderr
    HookManager.init File.join(@path, "hooks")
    UpdateManager.init
    SourceManager.init
    PollManager.init
    LabelManager.init File.join(@path, "labels.txt")
    ContactManager.init File.join(@path, "contacts.txt")
    Index.init File.join(@path, "xapian")
    Index.load
    @source = DummySource.new("sup-test://test_thread_view_mode")
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

    ## Scroll to the attachment and save it to a directory.
    destdir = File.join(@path, "saved2")
    Dir.mkdir destdir
    stub(BufferManager.instance).ask(:filename, "Save attachment to file or directory: ", "#{ENV["HOME"]}/sup_.travis.yml") { destdir }
    stub(BufferManager.instance).flash("Successfully wrote #{destdir}/sup_.travis.yml.")
    assert_equal "x Attachment: sup/.travis.yml (text/x-yaml; 260B)", mode[10][0][1]
    mode.send :set_cursor_pos, 10
    mode.save_to_disk
    expected_path = File.join destdir, "sup_.travis.yml"
    assert File.exist? expected_path
    assert_equal 260, File.size(expected_path)
  end
end

end
