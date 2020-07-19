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
    source = DummySource.new("sup-test://test_simple_message")
    source.messages = [ fixture_path('simple-message.eml') ]
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
    source = DummySource.new("sup-test://test_multipart_message")
    source.messages = [ fixture_path('multi-part.eml') ]
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
    source = DummySource.new("sup-test://test_broken_message_1")
    source.messages = [ fixture_path('missing-from-to.eml') ]
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
    source = DummySource.new("sup-test://test_broken_message_1")
    source.messages = [ fixture_path('no-body.eml') ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    # read the message body chunks: no errors should reach this level

    chunks = sup_message.load_from_source!

    assert_empty(chunks)
  end

  def test_multipart_message_2
    source = DummySource.new("sup-test://test_multipart_message_2")
    source.messages = [ fixture_path('multi-part-2.eml') ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    chunks = sup_message.load_from_source! # read the message body chunks

    # TODO: Add more asserts
  end

  def test_text_attachment_decoding
    source = DummySource.new("sup-test://test_text_attachment_decoding")
    source.messages = [ fixture_path('text-attachments-with-charset.eml') ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    chunks = sup_message.load_from_source!
    assert_equal(5, chunks.length)
    assert(chunks[0].is_a? Redwood::Chunk::Text)
    ## The first attachment declares charset=us-ascii
    assert(chunks[1].is_a? Redwood::Chunk::Attachment)
    assert_equal(["This is ASCII"], chunks[1].lines)
    ## The second attachment declares charset=koi8-r and has some Cyrillic
    assert(chunks[2].is_a? Redwood::Chunk::Attachment)
    assert_equal(["\u041f\u0440\u0438\u0432\u0435\u0442"], chunks[2].lines)
    ## The third attachment declares charset=utf-8 and has an emoji
    assert(chunks[3].is_a? Redwood::Chunk::Attachment)
    assert_equal(["\u{1f602}"], chunks[3].lines)
    ## The fourth attachment declares no charset and has a non-ASCII byte,
    ## which will be replaced with U+FFFD REPLACEMENT CHARACTER
    assert(chunks[4].is_a? Redwood::Chunk::Attachment)
    assert_equal(["Embedded\ufffdgarbage"], chunks[4].lines)
  end

  def test_mailing_list_header
    source = DummySource.new("sup-test://test_mailing_list_header")
    source.messages = [ fixture_path('mailing-list-header.eml') ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    assert(sup_message.list_subscribe.nil?)
    assert_equal("<https://lists.openembedded.org/g/openembedded-devel/unsub>",
                 sup_message.list_unsubscribe)
    assert_equal("openembedded-devel@lists.openembedded.org", sup_message.list_address.email)
    assert_equal("openembedded-devel", sup_message.list_address.name)
  end

  def test_blank_header_lines
    source = DummySource.new("sup-test://test_blank_header_lines")
    source.messages = [ fixture_path('blank-header-fields.eml') ]
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

  def test_rfc2047_header_encoding
    source = DummySource.new("sup-test://test_rfc2047_header_encoding")
    source.messages = [ fixture_path("rfc2047-header-encoding.eml") ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    assert_equal("Hans Martin Djupvik, Ingrid Bø, Ирина Сидорова, Jesper Berg " +
                 "bad: =?UTF16?q?badcharsetname?==?US-ASCII?b?/w?=",
                 sup_message.subj)
  end

  def test_nonascii_header
    ## Headers are supposed to be 7-bit ASCII, with non-ASCII characters encoded
    ## using RFC2047 header encoding. But spammers sometimes send high bytes in
    ## the headers. They will be replaced with U+FFFD REPLACEMENT CHARACTER.
    source = DummySource.new("sup-test://test_nonascii_header")
    source.messages = [ fixture_path("non-ascii-header.eml") ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    assert_equal("SPAM \ufffd", sup_message.from.name)
    assert_equal("spammer@example.com", sup_message.from.email)
    assert_equal("spam \ufffd spam", sup_message.subj)
  end

  def test_nonascii_header_in_nested_message
    source = DummySource.new("sup-test://test_nonascii_header_in_nested_message")
    source.messages = [ fixture_path("non-ascii-header-in-nested-message.eml") ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    chunks = sup_message.load_from_source!

    assert_equal(3, chunks.length)

    assert(chunks[0].is_a? Redwood::Chunk::Text)

    assert(chunks[1].is_a? Redwood::Chunk::EnclosedMessage)
    assert_equal(4, chunks[1].lines.length)
    assert_equal("From: SPAM \ufffd <spammer@example.com>", chunks[1].lines[0])
    assert_equal("To: enclosed <enclosed@example.invalid>", chunks[1].lines[1])
    assert_equal("Subject: spam \ufffd spam", chunks[1].lines[3])

    assert(chunks[2].is_a? Redwood::Chunk::Text)
    assert_equal(1, chunks[2].lines.length)
    assert_equal("This is a spam.", chunks[2].lines[0])
  end

  def test_embedded_message
    source = DummySource.new("sup-test://test_embedded_message")
    source.messages = [ fixture_path("embedded-message.eml") ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)

    chunks = sup_message.load_from_source!
    assert_equal(3, chunks.length)

    assert_equal("sender@example.com", sup_message.from.email)
    assert_equal("Sender", sup_message.from.name)
    assert_equal(1, sup_message.to.length)
    assert_equal("recipient@example.invalid", sup_message.to[0].email)
    assert_equal("recipient", sup_message.to[0].name)
    assert_equal("Email with embedded message", sup_message.subj)

    assert(chunks[0].is_a? Redwood::Chunk::Text)
    assert_equal("Example outer message.", chunks[0].lines[0])
    assert_equal("Example second line.", chunks[0].lines[1])

    assert(chunks[1].is_a? Redwood::Chunk::EnclosedMessage)
    assert_equal(4, chunks[1].lines.length)
    assert_equal("From: Embed sender <embed@example.com>", chunks[1].lines[0])
    assert_equal("To: rcpt2 <rcpt2@example.invalid>", chunks[1].lines[1])
    assert_equal("Date: ", chunks[1].lines[2][0..5])
    assert_equal(
      Time.rfc2822("Wed, 15 Jul 2020 12:34:56 +0000"),
      Time.rfc2822(chunks[1].lines[2][6..-1])
    )
    assert_equal("Subject: Embedded subject line", chunks[1].lines[3])

    assert(chunks[2].is_a? Redwood::Chunk::Text)
    assert_equal(2, chunks[2].lines.length)
    assert_equal("Example embedded message.", chunks[2].lines[0])
    assert_equal("Second line.", chunks[2].lines[1])
  end

  def test_malicious_attachment_names
    source = DummySource.new("sup-test://test_blank_header_lines")
    source.messages = [ fixture_path('malicious-attachment-names.eml') ]
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

  def test_zimbra_quote_with_bottom_post
    # Zimbra does an Outlook-style "Original Message" delimiter and then *also*
    # prefixes each quoted line with a > marker. That's okay until the sender
    # tries to do the right thing and reply after the quote.
    # In this case we want to just look at the > markers when determining where
    # the quoted chunk ends.
    source = DummySource.new("sup-test://test_zimbra_quote_with_bottom_post")
    source.messages = [ fixture_path('zimbra-quote-with-bottom-post.eml') ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    chunks = sup_message.load_from_source!

    assert_equal(3, chunks.length)

    # TODO this chunk should ideally be part of the quote chunk after it.
    assert(chunks[0].is_a? Redwood::Chunk::Text)
    assert_equal(1, chunks[0].lines.length)
    assert_equal("----- Original Message -----", chunks[0].lines.first)

    assert(chunks[1].is_a? Redwood::Chunk::Quote)

    assert(chunks[2].is_a? Redwood::Chunk::Text)
    assert_equal(3, chunks[2].lines.length)
    assert_equal("This is the reply from the Zimbra user.",
                 chunks[2].lines[2])
  end
end

end

# vim:noai:ts=2:sw=2:
