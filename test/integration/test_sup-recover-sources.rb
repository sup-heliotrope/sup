require "test_helper"
require "sup"
require "yaml"

class TestSupRecoverSources < Minitest::Test
  def setup
    @path = Dir.mktmpdir

    @maildir = File.join @path, "test_maildir"
    Dir.mkdir @maildir
    %w[cur new tmp].each do |subdir|
      Dir.mkdir (File.join @maildir, subdir)
    end
    msg_path = File.join @maildir, "new", "123.hostname"
    FileUtils.copy_file fixture_path("simple-message.eml"), msg_path

    @mbox = File.join @path, "test_mbox"
    File.open(@mbox, "wb") do |f|
      f.puts "From test@test #{Time.now.asctime}"
      f.puts File.read(fixture_path("simple-message.eml"))
    end

    _out, _err = capture_subprocess_io do
      assert system({"SUP_BASE" => @path}, "bin/sup-add", "maildir://#{@maildir}")
      assert system({"SUP_BASE" => @path}, "bin/sup-add", "mbox://#{@mbox}")
      assert system({"SUP_BASE" => @path}, "bin/sup-sync")
    end
  end

  def teardown
    FileUtils.rm_r @path
  end

  def test_recover_sources
    File.delete File.join(@path, "sources.yaml")
    source_uris = ["maildir://#{@maildir}", "mbox://#{@mbox}"]
    out, _err = capture_subprocess_io do
      assert system({"SUP_BASE" => @path}, "bin/sup-recover-sources", *source_uris)
    end
    assert_equal "assigned #{source_uris[0]} to 1\n", out.lines[0]
    assert_equal "assigned #{source_uris[1]} to 2\n", out.lines[1]

    sources_fn = File.join @path, "sources.yaml"
    sources_yaml =
      if YAML.respond_to?(:unsafe_load_file)  # Ruby 3.1+
        YAML::unsafe_load_file sources_fn
      else
        YAML::load_file sources_fn
      end
    assert_equal 2, sources_yaml.length
    assert_instance_of Redwood::Maildir, sources_yaml[0]
    assert_equal source_uris[0], sources_yaml[0].uri
    assert_equal 1, sources_yaml[0].id
    assert_instance_of Redwood::MBox, sources_yaml[1]
    assert_equal source_uris[1], sources_yaml[1].uri
    assert_equal 2, sources_yaml[1].id
  end

  def test_noop
    ## All sources are already defined in sources.yaml so there is nothing to recover.
    ## It should do nothing.
    source_uris = ["maildir://#{@maildir}", "mbox://#{@mbox}"]
    out, _err = capture_subprocess_io do
      assert system({"SUP_BASE" => @path}, "bin/sup-recover-sources", *source_uris)
    end
    assert out.empty?
  end
end
