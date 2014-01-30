#!/usr/bin/ruby
# encoding: utf-8

require 'test_helper'
require 'sup'
require 'stringio'

require 'dummy_source'

# override File.exists? to make it work with StringIO for testing.
# FIXME: do aliasing to avoid breaking this when sup moves from
# File.exists? to File.exist?

class File

  def File.exists? file
    # puts "fake File::exists?"

    if file.is_a?(StringIO)
      return false
    end
    # use the different function
    File.exist?(file)
  end

end

module Redwood

  # monkey patch the MBox source to work without the index.
  require 'sup/mbox'
  class MBox
    def first_new_message
      0
    end

    def my_ensure_open
      @f = File.open @path, 'rb' if @f.nil?
    end
  end

class TestMessagesDir < ::Minitest::Unit::TestCase

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
    File.open 'test/messages/binary-content-transfer-encoding-2.eml' do |f|
      message = f.read
    end

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
    File.open 'test/messages/bad-content-transfer-encoding-1.eml' do |f|
      message = f.read
    end

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
    File.open 'test/messages/missing-line.eml' do |f|
      message = f.read
    end

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
  def test_weird_header_encoding
    message = ''
    File.open 'test/messages/weird-encoding-in-header-field.eml', "r:UTF-8" do |f|
      message = f.read
    end

    #message.force_encoding 'UTF-8'

    source = DummySource.new("sup-test://test_messages")
    source.messages = [ message ]
    source_info = 0


    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    from = sup_message.from
    # "from" is just a simple person item

    assert_equal("foo@example.org", from.email)
    #assert_equal("Fake Sender", from.name)

    to = sup_message.to[0]
    test_to = "tesæt@example.org"

    assert_equal(test_to, to.email)

    subj = sup_message.subj
    test_subj = "here comes a weird char: õ"
    assert_equal(test_subj, subj)

    chunks = sup_message.load_from_source!
    indexable_chunks = sup_message.indexable_chunks

    # there should be only one chunk
    #assert_equal(1, chunks.length)

    lines = chunks[0].lines

    # check if body content includes some of the expected text
    assert (lines.join.include? "check out: "), "Body message does not match expected value"
  end



  def test_bad_address_field

    testmsg = File.join(File.dirname(__FILE__), 'messages/bad-address-spam.eml')
    source = MBox.new ("mbox:///#{testmsg}")
    source.my_ensure_open
    source_info = 0

    sup_message = nil

    source.poll do |sym, args|
      assert_equal(sym, :add)
      sup_message = Message.build_from_source source, args[:info]
    end

    from = sup_message.from
    # "from" is just a simple person item

    assert_equal("hbvv@yahoo.com", from.email)
    #assert_equal("Fake Sender", from.name)

    to = sup_message.to[0]
    test_to = "a@b.c"

    assert_equal(test_to, to.email)

    subj = sup_message.subj
    test_subj = "here comes a weird char: õ"
    #assert_equal(test_subj, subj)

    chunks = sup_message.load_from_source!
    indexable_chunks = sup_message.indexable_chunks

    # there should be only one chunk
    #assert_equal(1, chunks.length)

    lines = chunks[0].lines

    # check if body content includes some of the expected text
    #assert (lines.join.include? "check out: "), "Body message does not match expected value"
  end
end

end

# vim:noai:ts=2:sw=2:
