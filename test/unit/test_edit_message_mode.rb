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
    envelope.header["Content-Type"] = "multipart/signed; protocol=testdummy"
    envelope.add_part payload
    envelope
  end
end

class TestEditMessageMode < Minitest::Test
  def setup
    $config = {}
    @path = Dir.mktmpdir
    Redwood::HookManager.init File.join(@path, "hooks")
    Redwood::AccountManager.init :default => {name: "test", email: "sender@example.invalid"}
    Redwood::CryptoManager.instance_variable_set :@instance, DummyCryptoManager.new
  end

  def teardown
    Redwood::CryptoManager.deinstantiate!
    Redwood::AccountManager.deinstantiate!
    Redwood::HookManager.deinstantiate!
    FileUtils.rm_r @path
    $config = nil
  end

  def test_attachment_content_transfer_encoding_signed
    ## RMail::Message#make_attachment will choose
    ## Content-Transfer-Encoding: 8bit for a CSV file.
    attachment_filename = File.join @path, "dummy.csv"
    ## Include some high bytes in the attachment contents in order to
    ## exercise quote-printable transfer encoding.
    File.write attachment_filename, "löl,\ntest,\n"

    opts = {
      :header => {
        "From" => "sender@example.invalid",
        "To" => "recip@example.invalid",
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
end
