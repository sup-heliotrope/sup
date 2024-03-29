class TestSupAdd < Minitest::Test

  def setup
    @path = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_r @path
  end

  def test_can_add_maildir_source
    _out, _err = capture_subprocess_io do
      assert system({"SUP_BASE" => @path}, "bin/sup-add", "maildir:///some/path")
    end

    generated_sources_yaml = File.read "#{@path}/sources.yaml"
    assert_equal <<EOS, generated_sources_yaml
---
- !<tag:supmua.org,2006-10-01/Redwood/Maildir>
  uri: maildir:///some/path
  usual: true
  archived: false
  sync_back: true
  id: 1
  labels: []
EOS
  end

  def test_fixes_old_tag_uri_syntax
    File.write "#{@path}/sources.yaml", <<EOS
---
- !supmua.org,2006-10-01/Redwood/Maildir
  uri: maildir:/some/path
  usual: true
  archived: false
  sync_back: true
  id: 1
  labels: []
EOS
    _out, _err = capture_subprocess_io do
      assert system({"SUP_BASE" => @path}, "bin/sup-add", "maildir:///other/path")
    end

    generated_sources_yaml = File.read "#{@path}/sources.yaml"
    assert_equal <<EOS, generated_sources_yaml
---
- !<tag:supmua.org,2006-10-01/Redwood/Maildir>
  uri: maildir:/some/path
  usual: true
  archived: false
  sync_back: true
  id: 1
  labels: []
- !<tag:supmua.org,2006-10-01/Redwood/Maildir>
  uri: maildir:///other/path
  usual: true
  archived: false
  sync_back: true
  id: 2
  labels: []
EOS
  end

  ## https://github.com/sup-heliotrope/sup/issues/545
  def test_source_with_invalid_uri_chars_in_path
    _out, _err = capture_subprocess_io do
      assert system({"SUP_BASE" => @path}, "bin/sup-add", "maildir:~/.mail/gmail/[Gmail]/.All Mail/")
    end

    generated_sources_yaml = File.read "#{@path}/sources.yaml"
    assert_equal <<EOS, generated_sources_yaml
---
- !<tag:supmua.org,2006-10-01/Redwood/Maildir>
  uri: maildir:~/.mail/gmail/[Gmail]/.All Mail/
  usual: true
  archived: false
  sync_back: true
  id: 1
  labels: []
EOS
  end

end
