require "test_helper"

class TestSupSyncBackMaildir < Minitest::Test

  def setup
    @path = Dir.mktmpdir

    @maildir = File.join @path, "test_maildir"
    Dir.mkdir @maildir
    %w[cur new tmp].each do |subdir|
      Dir.mkdir (File.join @maildir, subdir)
    end
    msg_path = File.join @maildir, "new", "123.hostname"
    FileUtils.copy_file fixture_path("simple-message.eml"), msg_path

    _out, _err = capture_subprocess_io do
      assert system({"SUP_BASE" => @path}, "bin/sup-add", "maildir://#{@maildir}")
      assert system({"SUP_BASE" => @path}, "bin/sup-sync")
    end
  end

  def teardown
    FileUtils.rm_r @path
  end

  def test_it_syncs_seen_unread_flags
    _out, _err = capture_subprocess_io do
      assert system({"SUP_BASE" => @path},
                    "bin/sup-tweak-labels",
                    "--all-sources",
                    "--add=replied",
                    "--remove=unread")
      assert system({"SUP_BASE" => @path}, "bin/sup-sync-back-maildir", "--no-confirm")
    end

    refute File.exist? (File.join @maildir, "new", "123.hostname")
    assert File.exist? (File.join @maildir, "cur", "123.hostname:2,RS")
  end

end
