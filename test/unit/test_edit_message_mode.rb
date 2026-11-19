require "test_helper"

require "sup"

class DummySelector
  attr_accessor :val
  def initialize val
    @val = val
  end
end

class DummyCryptoManager
  def have_crypto?; true; end
  def sign from, to, payload
    envelope = RMail::Message.new
    envelope.header["Content-Type"] = +"multipart/signed; protocol=testdummy"
    envelope.add_part payload
    envelope
  end
end

class TestEditMessageMode < Minitest::Test
  def setup
    $config = {}
    @path = Dir.mktmpdir
    Redwood::HookManager.init File.join(@path, "hooks")
    account = {
      :name => +"test",
      :email => +"sender@example.invalid",
      :sendmail => "/bin/false",
    }
    Redwood::AccountManager.init :default => account
    Redwood::CryptoManager.instance_variable_set :@instance, DummyCryptoManager.new
  end

  def teardown
    Redwood::CryptoManager.deinstantiate!
    Redwood::AccountManager.deinstantiate!
    Redwood::HookManager.deinstantiate!
    FileUtils.rm_r @path
    $config = nil
  end

  def test_basic_message
    opts = {
      :header => {
        "From" => +"sender@example.invalid",
        "To" => +"recip@example.invalid",
      },
      :body => ["hello friends"],
    }
    mode = Redwood::EditMessageMode.new opts

    msg = mode.send :build_message, Time.now
    refute msg.multipart?
    assert_equal "hello friends\n", msg.body
    assert_equal "text/plain; charset=UTF-8", msg.header["Content-Type"]
    assert_equal "8bit", msg.header["Content-Transfer-Encoding"]
    assert_equal "1.0", msg.header["MIME-Version"]
    assert_match(/^Sup\//, msg.header["User-Agent"])
    refute_nil msg.header["Date"]
    refute_nil msg.header["Message-Id"]
  end

  def test_attachment_content_transfer_encoding
    ## RMail::Message#make_attachment will choose
    ## Content-Transfer-Encoding: 8bit for a CSV file.
    ## If we're not GPG signing or encrypting then the attachment will be sent
    ## as is. Note this assumes the SMTP servers in the delivery path all
    ## support the 8BITMIME extension.
    attachment_content = "löl,\ntest,\n"
    attachment_filename = File.join @path, "dummy.csv"
    File.write attachment_filename, attachment_content

    opts = {
      :header => {
        "From" => +"sender@example.invalid",
        "To" => +"recip@example.invalid",
      },
      :attachments => {
        "dummy.csv" => RMail::Message.make_file_attachment(attachment_filename),
      },
    }
    mode = Redwood::EditMessageMode.new opts

    msg = mode.send :build_message, Time.now
    attachment = msg.part(1)
    assert_equal attachment_content.b, attachment.body
    assert_equal "8bit", attachment.header["Content-Transfer-Encoding"]
  end

  def test_attachment_content_transfer_encoding_signed
    attachment_filename = File.join @path, "dummy.csv"
    ## Include some high bytes in the attachment contents in order to
    ## exercise quote-printable transfer encoding.
    File.write attachment_filename, "löl,\ntest,\n"

    opts = {
      :header => {
        "From" => +"sender@example.invalid",
        "To" => +"recip@example.invalid",
      },
      :attachments => {
        "dummy.csv" => RMail::Message.make_file_attachment(attachment_filename),
      },
    }
    mode = Redwood::EditMessageMode.new opts
    mode.instance_variable_set :@crypto_selector, DummySelector.new(:sign)

    msg = mode.send :build_message, Time.now
    ## The outermost message is a (fake) multipart/signed created by DummyCryptoManager#send.
    ## Inside that we have our inline message at index 0 and CSV attachment at index 1.
    attachment = msg.part(0).part(1)
    ## The attachment should have been re-encoded as quoted-printable for GPG signing.
    assert_equal "l=C3=B6l,\ntest,\n", attachment.body
    ## There shouldn't be multiple Content-Transfer-Encoding headers.
    ## This was: https://github.com/sup-heliotrope/sup/issues/502
    assert_equal ["quoted-printable"], attachment.header.fetch_all("Content-Transfer-Encoding")
  end

  ## https://github.com/sup-heliotrope/sup/issues/135
  def test_attachment_8bit_non_utf8
    body_content = "löl noñ-ÀSCII bodý"
    ## CP1251 is not UTF-8 compatible.
    ## This is a CSV only due to a quirk of mime-types, which wants to use 8bit for text/csv
    ## (whereas text/plain is quoted-printable).
    attachment_content = "С днем рождения!\n".encode("cp1251")
    attachment_filename = File.join @path, "cp1251.csv"
    File.write attachment_filename, attachment_content

    opts = {
      :header => {
        "From" => +"sender@example.invalid",
        "To" => +"recip@example.invalid",
      },
      :attachments => {
        "cp1251.csv" => RMail::Message.make_file_attachment(attachment_filename),
      },
      :body => [body_content],
    }
    mode = Redwood::EditMessageMode.new opts

    msg = mode.send :build_message, Time.now
    inline = msg.part(0)
    assert_equal body_content.b + "\n", inline.body
    assert_equal "text/plain; charset=UTF-8", inline.header["Content-Type"]
    assert_equal "inline", inline.header["Content-Disposition"]
    assert_equal "8bit", inline.header["Content-Transfer-Encoding"]
    attachment = msg.part(1)
    assert_equal attachment_content.b, attachment.body
    assert_equal 'text/csv; name="cp1251.csv"', attachment.header["Content-Type"]
    assert_equal 'attachment; filename="cp1251.csv"', attachment.header["Content-Disposition"]
    assert_equal "8bit", attachment.header["Content-Transfer-Encoding"]

    ## Also check the serialized message, which is what the send_message method uses.
    assert msg.to_s.lines.include? body_content.b + "\n"
    assert msg.to_s.lines.include? "Content-Type: text/csv; name=\"cp1251.csv\"\n"
    assert msg.to_s.lines.include? attachment_content.b
  end
end
