#!/usr/bin/ruby

require 'test_helper'
require 'sup'
require 'stringio'

require 'dummy_source'

module Redwood

class TestMessage < Minitest::Test

  def setup
    @path = Dir.mktmpdir
    Redwood::HookManager.init File.join(@path, 'hooks')
  end

  def teardown
    Redwood::HookManager.deinstantiate!
    FileUtils.rm_r @path
  end

  def test_simple_message
    message = fixture('simple-message.eml')

    source = DummySource.new("sup-test://test_simple_message")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    # see how well parsing the header went
    to = sup_message.to
    assert(to.is_a? Array)
    assert(to.first.is_a? Person)
    assert_equal(1, to.length)

    # sup doesn't do capitalized letters in email addresses
    assert_equal("fake_receiver@localhost", to[0].email)
    assert_equal("Fake Receiver", to[0].name)

    from = sup_message.from
    assert(from.is_a? Person)
    assert_equal("fake_sender@example.invalid", from.email)
    assert_equal("Fake Sender", from.name)

    subj = sup_message.subj
    assert_equal("Re: Test message subject", subj)

    list_subscribe = sup_message.list_subscribe
    assert_equal("<mailto:example-subscribe@example.invalid>", list_subscribe)

    list_unsubscribe = sup_message.list_unsubscribe
    assert_equal("<mailto:example-unsubscribe@example.invalid>", list_unsubscribe)

    list_address = sup_message.list_address
    assert_equal("example@example.invalid", list_address.email)
    assert_equal("example", list_address.name)

    date = sup_message.date
    assert_equal(Time.parse("Sun, 9 Dec 2007 21:48:19 +0200"), date)

    id = sup_message.id
    assert_equal("20071209194819.GA25972@example.invalid", id)

    refs = sup_message.refs
    assert_equal(1, refs.length)
    assert_equal("E1J1Rvb-0006k2-CE@localhost.localdomain", refs[0])

    replytos = sup_message.replytos
    assert_equal(1, replytos.length)
    assert_equal("E1J1Rvb-0006k2-CE@localhost.localdomain", replytos[0])

    assert_empty(sup_message.cc)
    assert_empty(sup_message.bcc)

    recipient_email = sup_message.recipient_email
    assert_equal("fake_receiver@localhost", recipient_email)

    message_source = sup_message.source
    assert_equal(message_source, source)

    message_source_info = sup_message.source_info
    assert_equal(message_source_info, source_info)

    # read the message body chunks
    chunks = sup_message.load_from_source!

    # there should be only one chunk
    assert_equal(1, chunks.length)

    lines = chunks.first.lines

    # there should be only one line
    assert_equal(1, lines.length)

    assert_equal("Test message!", lines.first)
  end

  def test_multipart_message
    message = fixture('multi-part.eml')

    source = DummySource.new("sup-test://test_multipart_message")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    # read the message body chunks
    chunks = sup_message.load_from_source!

    # this time there should be four chunks: first the quoted part of
    # the message, then the non-quoted part, then the two attachments
    assert_equal(4, chunks.length)

    assert(chunks[0].is_a? Redwood::Chunk::Quote)
    assert(chunks[1].is_a? Redwood::Chunk::Text)
    assert(chunks[2].is_a? Redwood::Chunk::Attachment)
    assert(chunks[3].is_a? Redwood::Chunk::Attachment)

    # further testing of chunks will happen in test_message_chunks.rb
    # (possibly not yet implemented)

  end

  def test_broken_message_1
    message = fixture('missing-from-to.eml')

    source = DummySource.new("sup-test://test_broken_message_1")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    to = sup_message.to

    # there should no items, since the message doesn't have any recipients -- still not nil
    assert(!to.nil?)
    assert_empty(to)

    # from will have bogus values
    from = sup_message.from
    # very basic email address check
    assert_match(/\w+@\w+\.\w{2,4}/, from.email)
    refute_nil(from.name)

  end

  def test_broken_message_2
    message = fixture('no-body.eml')

    source = DummySource.new("sup-test://test_broken_message_1")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    # read the message body chunks: no errors should reach this level

    chunks = sup_message.load_from_source!

    assert_empty(chunks)
  end

  def test_multipart_message_2
    message = fixture('multi-part-2.eml')

    source = DummySource.new("sup-test://test_multipart_message_2")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    chunks = sup_message.load_from_source! # read the message body chunks

    # TODO: Add more asserts
  end

  def test_blank_header_lines
    message = fixture('blank-header-fields.eml')

    source = DummySource.new("sup-test://test_blank_header_lines")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    # See how well parsing the message ID went.
    id = sup_message.id
    assert_equal("D3C12B2AD838B44DA9D6B2CA334246D011E72A73A4@PA-EXMBX04.widget.com", id)

    # Look at another header field whose first line was blank.
    list_unsubscribe = sup_message.list_unsubscribe
    assert_equal("<http://mailman2.widget.com/mailman/listinfo/monitor-list>,\n\t" +
                 "<mailto:monitor-list-request@widget.com?subject=unsubscribe>",
                 list_unsubscribe)

  end

  def test_malicious_attachment_names
    message = fixture('malicious-attachment-names.eml')

    source = DummySource.new("sup-test://test_blank_header_lines")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    chunks = sup_message.load_from_source!

    # See if attachment filenames can be safely used for saving.
    # We do that by verifying that any folder-related character (/ or \)
    # are not interpreted: the filename must not be interpreted into a
    # path.
    fn = chunks[3].safe_filename
    assert_equal(fn, File.basename(fn))
  end
  # TODO: test different error cases, malformed messages etc.

  # TODO: test different quoting styles, see that they are all divided
  # to chunks properly

end

end

# vim:noai:ts=2:sw=2:
