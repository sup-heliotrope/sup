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
    assert_equal "text/html; name=\"test.html\"", a.header["Content-Type"]
    assert_equal "attachment; filename=\"test.html\"", a.header["Content-Disposition"]
    assert_equal "8bit", a.header["Content-Transfer-Encoding"]
  end

  def test_make_file_attachment_text_with_long_lines
    filename = File.join @path, "test.html"
    File.write filename, "a" * 1023

    a = RMail::Message.make_file_attachment(filename)
    assert_equal "text/html; name=\"test.html\"", a.header["Content-Type"]
    assert_equal "attachment; filename=\"test.html\"", a.header["Content-Disposition"]
    assert_equal "quoted-printable", a.header["Content-Transfer-Encoding"]

    qp_encoded = ("a" * 73 + "=\n") * 14 + "a=\n"
    assert_equal qp_encoded, a.body
  end
end
