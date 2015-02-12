require "test_helper"

class TestMbox < MiniTest::Test

  def setup
    @path = Dir.mktmpdir

    @test_message_1 = <<EOS
From sup-talk-bounces@rubyforge.org Mon Apr 27 12:56:18 2009
From: Bob <bob@bob.com>
To: Joe <joe@joe.com>

Hello there friend. How are you? Blah is blah blah.
I like mboxes, don't you?
EOS

  end

  def teardown
    ObjectSpace.each_object(Class).select {|a| a < Redwood::Singleton}.each do |klass|
      klass.deinstantiate! unless klass == Redwood::Logger
    end
    FileUtils.rm_r @path
  end

  def create_a_mbox(extra='')
    mbox = File.join(@path, "test_mbox#{extra}.mbox")
    File.write(mbox, @test_message_1)
    mbox
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

  def test_can_index_a_mbox_directory

    mbox = create_a_mbox
    start_sup_and_add_source MBox.new "mbox:#{mbox}"

    messages_in_index = []
    Index.instance.each_message {|a| messages_in_index << a}
    refute_empty messages_in_index, 'There are no messages in the index'
    test_message_without_first_line = @test_message_1.sub(/^.*\n/,'')
    assert_equal(messages_in_index.first.raw_message, test_message_without_first_line)

  end

  def test_can_index_a_mbox_directory_with_special_characters

    mbox = create_a_mbox URI_ENCODE_CHARS
    start_sup_and_add_source MBox.new "mbox:#{mbox}"

    messages_in_index = []
    Index.instance.each_message {|a| messages_in_index << a}
    refute_empty messages_in_index, 'There are no messages in the index'
    test_message_without_first_line = @test_message_1.sub(/^.*\n/,'')
    assert_equal(messages_in_index.first.raw_message, test_message_without_first_line)

  end

end
