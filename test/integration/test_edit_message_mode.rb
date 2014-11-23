# encoding: utf-8
require "test_helper"

class TestEditMessageAndDraft < MiniTest::Unit::TestCase

  def setup
    @path = Dir.mktmpdir

    Redwood::load_constants @path

    $config = load_config Redwood::CONFIG_FN
    @log_io = File.open(Redwood::LOG_FN, 'a')
    Redwood::Logger.add_sink @log_io
    Redwood::HookManager.init Redwood::HOOK_DIR
    Redwood::SentManager.init $config[:sent_source] || 'sup://sent'
    Redwood::ContactManager.init Redwood::CONTACT_FN
    Redwood::LabelManager.init Redwood::LABEL_FN
    Redwood::AccountManager.init $config[:accounts]
    Redwood::DraftManager.init Redwood::DRAFT_DIR
    Redwood::SearchManager.init Redwood::SEARCH_FN

    Redwood::managers.each { |x| x.init unless x.instantiated? }

    Index.init @path
    Index.load
    SourceManager.instance.instance_eval '@sources = {}'

    debug "adding draft source.."
    Redwood::SourceManager.add_source DraftManager.new_source
  end

  def teardown
    Redwood::Logger.remove_sink @log_io
    managers.each { |x| x.deinstantiate! if x.instantiated? }

    @log_io.close if @log_io

    ObjectSpace.each_object(Class).select {|a| a < Redwood::Singleton}.each do |klass|
      klass.deinstantiate! unless klass == Redwood::Logger
    end

    warn "removing #{@path}"
    FileUtils.rm_r @path # this doesn't seem to work properly
  end

  def test_draft_dir
    assert (File.directory? File.join(@path, 'drafts'))
  end

  def do_standard_tests nodelete
    # try to load message
    messages_in_index = []
    Index.instance.each_message {|a| messages_in_index << a}
    refute_empty messages_in_index, 'There are no messages in the index'

    refute_empty messages_in_index.select { |a| a.is_draft? }, 'There are no drafts in the index.'

    # there should not be more than one item in the index now
    assert (messages_in_index.count == 1)

    mydraft = messages_in_index[0]

    # load draft
    header, body = EditMessageMode.parse_file mydraft.draft_filename

    # remove message
    unless nodelete
      Index.delete mydraft.id

      messages_in_index = []
      Index.instance.each_message {|a| messages_in_index << a}
      assert_empty messages_in_index, 'Index should be empty'
    end
  end

  def write_and_load_draft msg, nodelete = false
    DraftManager.write_draft do |f|
      f.puts msg
    end

    do_standard_tests nodelete
  end

  def write_and_load_headers_body headers, body, msg_id, nodelete = false
    DraftManager.write_draft do |f|

      f.puts EditMessageMode.format_headers(headers).first
      f.puts <<EOS
Date: #{Time.now.rfc2822}
Message-Id: #{msg_id}
EOS

      f.puts
      f.puts EditMessageMode.sanitize_body(body.join("\n"))

    end

    do_standard_tests nodelete
  end

  def test_write_and_load_draft
    test_message_1 = <<EOS
From sup-talk-bounces@rubyforge.org Mon Apr 27 12:56:18 2009
From: Bob <bob@bob.com>
To: Joe <joe@joe.com>

Hello there friend. How are you? Blah is blah blah.
I like mboxes, don't you?
EOS

    write_and_load_draft test_message_1
  end

  def test_utf_8_msg
    utf_8_msg = <<EOS
From sup-talk-bounces@rubyforge.org Mon Apr 27 12:56:18 2009
From: Bob <bob@bob.com>
To: Joe <joe@joe.com>

here's some utf-8: ølååå

Hello there friend. How are you? Blah is blah blah.
I like mboxes, don't you?
EOS

    write_and_load_draft utf_8_msg

  end

  def test_utf_8_message_building
    headers = {"From" => "Bob <bob@bob.com>",
               "To" => "Joe <joe@joe.com>",
               "Subject" => "testing øæ",
    }

    msg_id = "test-draft-101"

    utf_8_msg = <<EOS
From sup-talk-bounces@rubyforge.org Mon Apr 27 12:56:18 2009
From: Bob <bob@bob.com>
To: Joe <joe@joe.com>

here's some utf-8: ølååå

Hello there friend. How are you? Blah is blah blah.
I like mboxes, don't you?
EOS

    body_lines = utf_8_msg.split("\n")

    write_and_load_headers_body headers, body_lines, msg_id, false
  end

  def test_bad_encoding
    headers = {"From" => "Bob <bob@bob.com>",
               "To" => "Joe <joe@joe.com>",
               "Subject" => "testing øæ",
    }

    msg_id = "test-draft-101"

    utf_8_msg = <<EOS
From sup-talk-bounces@rubyforge.org Mon Apr 27 12:56:18 2009
From: Bob <bob@bob.com>
To: Joe <joe@joe.com>

here's some utf-8: ølååå

Hello there friend. How are you? Blah is blah blah.
I like mboxes, don't you?
EOS

    body_lines = utf_8_msg.split("\n").each { |x| x.force_encoding('ASCII') }

    assert_raises ArgumentError do
      write_and_load_headers_body headers, body_lines, msg_id, false
    end

  end
end
