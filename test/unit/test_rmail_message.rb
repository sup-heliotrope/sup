require "test_helper"

require "sup"

class TestRMailMessage < Minitest::Test
  def setup
    @path = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_r @path
  end

  def test_make_file_attachment
    filename = File.join @path, "test.html"
    File.write filename, "<html></html>"

    a = RMail::Message.make_file_attachment(filename)
    assert_equal "text/html; charset=us-ascii; name=\"test.html\"", a.header["Content-Type"]
    assert_equal "attachment; filename=\"test.html\"", a.header["Content-Disposition"]
    assert_equal "7bit", a.header["Content-Transfer-Encoding"]
  end

  def test_make_file_attachment_text_with_long_lines
    skip "libmagic 5.40 misdetects this attachment as application/octet-stream" if Magic.version == 540
    filename = File.join @path, "test.html"
    File.write filename, "a" * 1023

    a = RMail::Message.make_file_attachment(filename)
    assert_equal "text/plain; charset=us-ascii; name=\"test.html\"", a.header["Content-Type"]
    assert_equal "attachment; filename=\"test.html\"", a.header["Content-Disposition"]
    assert_equal "quoted-printable", a.header["Content-Transfer-Encoding"]

    qp_encoded = ("a" * 73 + "=\n") * 14 + "a=\n"
    assert_equal qp_encoded, a.body
  end

  def test_make_file_attachment_mimetype_guessing
    [
      ["git-format.patch", 'application/mbox; charset=us-ascii; name="git-format.patch"', "7bit"],
      ["traditional.patch", 'text/x-diff; charset=us-ascii; name="traditional.patch"', "7bit"],
      ["configure", 'text/x-shellscript; charset=us-ascii; name="configure"', "7bit"],
      ["hello.c", 'text/x-c; charset=utf-8; name="hello.c"', "8bit"],
      ["Makefile", 'text/plain; charset=us-ascii; name="Makefile"', "7bit"],
      ["Dockerfile", 'text/plain; charset=us-ascii; name="Dockerfile"', "7bit"],
      ["Cargo.toml", 'text/plain; charset=us-ascii; name="Cargo.toml"', "7bit"],
      ["firmware.hex", 'text/x-hex; charset=us-ascii; name="firmware.hex"', "7bit"],
      ["go.mod", 'text/plain; charset=us-ascii; name="go.mod"', "7bit"],
      ["Hello.pm", 'text/plain; charset=us-ascii; name="Hello.pm"', "7bit"],
      ["hello.py", 'text/x-script.python; charset=us-ascii; name="hello.py"', "7bit"],
      ["main.rs", 'text/x-c; charset=us-ascii; name="main.rs"', "7bit"],
      ["main.ts", 'text/plain; charset=us-ascii; name="main.ts"', "7bit"],
      ["koi8.txt", 'text/plain; charset=iso-8859-1; name="koi8.txt"', "8bit"],
      ["cp1251.txt", 'text/plain; charset=iso-8859-1; name="cp1251.txt"', "8bit"],
      ["minimal.pdf", 'application/pdf; charset=us-ascii; name="minimal.pdf"', "base64"],
      ["board.dtb", 'application/octet-stream; name="board.dtb"', "base64"],
      ["hello", 'application/x-executable; name="hello"', "base64"],
      ["module.wasm", 'application/wasm; name="module.wasm"', "base64"],
      ["component.wasm", 'application/wasm; name="component.wasm"', "base64"],
    ].each do |fn, expected_content_type, expected_encoding|
      a = RMail::Message.make_file_attachment fixture_path("attachments/#{fn}")
      expected_content_type.sub!(/text\/x-hex/, "text/plain") unless Magic.version >= 546
      expected_content_type.sub!(/application\/mbox/, "text/x-diff") unless Magic.version >= 546
      expected_content_type.sub!(/application\/wasm/, "application/octet-stream") unless Magic.version >= 543
      expected_content_type.sub!(/application\/wasm/, "application/octet-stream") if fn == "module.wasm" and Magic.version >= 547
      expected_content_type.sub!(/application\/wasm/, "application/octet-stream") if fn == "component.wasm" and Magic.version < 547
      assert_equal expected_content_type, a.header["Content-Type"]
      assert_equal expected_encoding, a.header["Content-Transfer-Encoding"]
      assert_equal File.binread(fixture_path("attachments/#{fn}")), a.decode
    end
  end

  def test_make_file_attachment_nested_emails
    [
      ["simple-message.eml", 'message/rfc822; charset=us-ascii; name="simple-message.eml"', "7bit"],
      ["utf8-header.eml", 'message/rfc822; charset=utf-8; name="utf8-header.eml"', "8bit"],
    ].each do |fn, expected_content_type, expected_encoding|
      a = RMail::Message.make_file_attachment fixture_path(fn)
      assert_equal expected_content_type, a.header["Content-Type"]
      assert_equal expected_encoding, a.header["Content-Transfer-Encoding"]
      assert_equal File.binread(fixture_path(fn)), a.decode
    end
  end
end
