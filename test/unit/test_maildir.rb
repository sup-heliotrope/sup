require "test_helper"

class TestMaildir < Minitest::Test

  def setup
    @path = Dir.mktmpdir
    @maildir = File.join @path, 'test_maildir'
    ['', 'cur', 'new', 'tmp'].each do |dir|
      Dir.mkdir(File.join @maildir, dir)
    end
    @label_service = LabelService.new
    create_a_maildir_email(File.join(@maildir, 'cur'), <<EOS)
From sup-talk-bounces@rubyforge.org Mon Apr 27 12:56:18 2009
From: Bob <bob@bob.com>
To: a dear friend

Hello there friend. How are you?

From bob@bob.com Mon Apr 27 12:56:19 2009
From: Bob <bob@bob.com>
To: a dear friend

Hello again! Would you like to buy my products?
EOS

  end

  def teardown
    FileUtils.rm_r @path
  end

  def create_a_maildir_email(folder, content)
    File.write(File.join(folder, "#{Time.now.to_f}.hostname:2,S"), content)
  end

  def test_can_index_a_maildir_directory
    md = Maildir.new "maildir:#{@maildir}"
    start
    Index.init @path
    Index.load
    # SourceManager.instance.instance_eval '@sources = {}'
    # SourceManager.instance.add_source md
    # PollManager.poll_from md
    # Index.save
    require 'pry'; binding.pry
    assert_equal(false, true)
  end

  def test_can_index_a_maildir_directory_with_special_characters
    assert_equal(false, true)
  end

  def test_can_display_an_email_from_a_maildir_directory
    assert_equal(false, true)
  end

  def test_can_display_an_email_from_a_maildir_directory_with_special_characters
    assert_equal(false, true)
  end

end

