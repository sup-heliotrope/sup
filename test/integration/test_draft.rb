require "sup"
require "test_helper"

class TestDraft < Minitest::Test
  include Redwood

  def setup
    @path = Dir.mktmpdir
    start
    @draft_dir = File.join @path, "drafts"
    @test_message_1 = <<EOS
From: Some Person <someone@example.invalid>
To:
Cc:
Bcc:
Subject: draft
Date: Fri, 11 Apr 2025 22:34:05 +1000
Message-ID: <123@example.invalid>

My incomplete message
EOS
    DraftManager.instance.instance_eval "@dir = '#{@draft_dir}'"
    Index.init @path
    Index.load
    SourceManager.instance.instance_eval "@sources = {}"
    @draft_source = DraftManager.new_source
    SourceManager.add_source @draft_source
  end

  def teardown
    ObjectSpace.each_object(Class).select {|a| a < Redwood::Singleton}.each do |klass|
      klass.deinstantiate! unless klass == Redwood::Logger
    end
    FileUtils.rm_r @path
  end

  def test_write_draft
    DraftManager.write_draft { |f| f.write @test_message_1 }

    draft_filename = File.join @draft_dir, "0"
    assert File.exist? draft_filename
    assert_equal @test_message_1, (File.read draft_filename)

    ## Check that it is loaded back into the index successfully too.
    messages_in_index = Index.instance.enum_for(:each_message).to_a
    assert_equal @test_message_1, messages_in_index.first.raw_message
    assert_equal [:draft, :inbox].to_set, messages_in_index.first.labels
  end

  def test_discard_draft
    DraftManager.write_draft { |f| f.write @test_message_1 }
    draft_filename = File.join @draft_dir, "0"
    assert File.exist? draft_filename
    message_in_index = Index.instance.enum_for(:each_message).to_a.first

    DraftManager.discard message_in_index
    refute File.exist? draft_filename
  end

  def test_discard_already_deleted_from_disk
    DraftManager.write_draft { |f| f.write @test_message_1 }
    draft_filename = File.join @draft_dir, "0"
    assert File.exist? draft_filename
    message_in_index = Index.instance.enum_for(:each_message).to_a.first

    File.delete draft_filename

    DraftManager.discard message_in_index
    refute File.exist? draft_filename
  end

  def test_load_malformed_draft
    ## Sup always writes drafts by serialising a Message, meaning the draft is
    ## guaranteed to have certain headers like Date. But it's always possible
    ## for the user to edit the draft directly on the filesystem and leave it
    ## in some kind of malformed state. Sup should handle it without crashing.
    draft_filename = File.join @draft_dir, "0"
    fallback_date = Time.new 2025, 5, 3, 15, 47, 41
    File.write draft_filename, <<EOS
Some-Header: Value

body
EOS
    File.utime fallback_date, fallback_date, draft_filename
    PollManager.poll_from @draft_source
    messages_in_index = Index.instance.enum_for(:each_message).to_a
    assert_equal "", messages_in_index[0].subj
    assert_equal fallback_date, messages_in_index[0].date

    File.write (File.join @draft_dir, "1"), <<EOS
missing a header!
EOS
    PollManager.poll_from @draft_source
    messages_in_index = Index.instance.enum_for(:each_message).to_a
    assert_equal "", messages_in_index[0].subj

    File.write (File.join @draft_dir, "2"), ""
    PollManager.poll_from @draft_source
    messages_in_index = Index.instance.enum_for(:each_message).to_a
    assert_equal "", messages_in_index[0].subj
  end
end
