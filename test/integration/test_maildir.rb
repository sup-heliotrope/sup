require "test_helper"

class TestMaildir < Minitest::Test

  def setup
    @path = Dir.mktmpdir

    @test_message_1 = <<EOS
From: Bob <bob@bob.com>
To: a dear friend

Hello there friend. How are you? Blah is blah blah.
Wow. Maildir FTW, am I right?
EOS

  end

  def teardown
    ObjectSpace.each_object(Class).select {|a| a < Redwood::Singleton}.each do |klass|
      klass.deinstantiate! unless klass == Redwood::Logger
    end
    FileUtils.rm_r @path
  end

  def create_a_maildir(extra='')
    maildir = File.join @path, "test_maildir#{extra}"
    ['', 'cur', 'new', 'tmp'].each do |dir|
      Dir.mkdir(File.join maildir, dir)
    end
    maildir
  end

  def create_a_maildir_email(folder, content)
    File.write(File.join(folder, "#{Time.now.to_f}.hostname:2,S"), content)
  end

  def start_sup_and_add_source(source)
    start
    Index.init @path
    Index.load
    SourceManager.instance.instance_eval '@sources = {}'
    SourceManager.instance.add_source source
    PollManager.poll_from source
  end

  # and now, let the tests begin!

  def test_can_index_a_maildir_directory

    maildir = create_a_maildir
    create_a_maildir_email(File.join(maildir, 'cur'), @test_message_1)
    start_sup_and_add_source Maildir.new "maildir:#{maildir}"

    messages_in_index = []
    Index.instance.each_message {|a| messages_in_index << a}
    refute_empty messages_in_index, 'There are no messages in the index'
    assert_equal(messages_in_index.first.raw_message, @test_message_1)

  end

  def test_can_index_a_maildir_directory_with_special_characters

    maildir = create_a_maildir URI_ENCODE_CHARS
    create_a_maildir_email(File.join(maildir, 'cur'), @test_message_1)
    start_sup_and_add_source Maildir.new "maildir:#{maildir}"

    messages_in_index = []
    Index.instance.each_message {|a| messages_in_index << a}
    refute_empty messages_in_index, 'There are no messages in the index'
    assert_equal(messages_in_index.first.raw_message, @test_message_1)

  end

end

