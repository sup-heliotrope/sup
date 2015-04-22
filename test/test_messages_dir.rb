#!/usr/bin/ruby

require 'test_helper'
require 'sup'
require 'stringio'

require 'dummy_source'

module Redwood

class TestMessagesDir < ::Minitest::Test

  def setup
    @path = Dir.mktmpdir
    Redwood::HookManager.init File.join(@path, 'hooks')
  end

  def teardown
    Redwood::HookManager.deinstantiate!
    FileUtils.rm_r @path
  end

  def test_binary_content_transfer_encoding
    message = ''
    File.open('test/fixtures/binary-content-transfer-encoding-2.eml') { |f| message = f.read }

    source = DummySource.new("sup-test://test_messages")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    from = sup_message.from
    # "from" is just a simple person item

    assert_equal("foo@example.org", from.email)
    #assert_equal("Fake Sender", from.name)

    subj = sup_message.subj
    assert_equal("Important", subj)

    chunks = sup_message.load_from_source!
    indexable_chunks = sup_message.indexable_chunks

    # there should be only one chunk
    #assert_equal(1, chunks.length)

    lines = chunks[0].lines

    # lines should contain an error message
    assert (lines.join.include? "An error occurred while loading this message."), "This message should not load successfully"
  end

  def test_bad_content_transfer_encoding
    message = ''
    File.open('test/fixtures/bad-content-transfer-encoding-1.eml') { |f| message = f.read }

    source = DummySource.new("sup-test://test_messages")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    from = sup_message.from
    # "from" is just a simple person item

    assert_equal("foo@example.org", from.email)
    #assert_equal("Fake Sender", from.name)

    subj = sup_message.subj
    assert_equal("Content-Transfer-Encoding:-bug in sup", subj)

    chunks = sup_message.load_from_source!
    indexable_chunks = sup_message.indexable_chunks

    # there should be only one chunk
    #assert_equal(1, chunks.length)

    lines = chunks[0].lines

    # lines should contain an error message
    assert (lines.join.include? "An error occurred while loading this message."), "This message should not load successfully"
  end

  def test_missing_line
    message = ''
    File.open('test/fixtures/missing-line.eml') { |f| message = f.read }

    source = DummySource.new("sup-test://test_messages")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    from = sup_message.from
    # "from" is just a simple person item

    assert_equal("foo@aol.com", from.email)
    #assert_equal("Fake Sender", from.name)

    subj = sup_message.subj
    assert_equal("Encoding bug", subj)

    chunks = sup_message.load_from_source!
    indexable_chunks = sup_message.indexable_chunks

    # there should be only one chunk
    #assert_equal(1, chunks.length)

    lines = chunks[0].lines

    badline = lines[0]
    assert (badline.display_length > 0), "The length of this line should greater than 0: #{badline}"

  end
end

end

# vim:noai:ts=2:sw=2:
