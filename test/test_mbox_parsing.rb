#!/usr/bin/ruby

require 'test/unit'
require 'sup'
require 'stringio'

include Redwood

class TestMessage < Test::Unit::TestCase
  def setup
  end

  def teardown
  end

  def test_normal_headers
    h = MBox.read_header StringIO.new(<<EOS)
From: Bob <bob@bob.com>
To: Sally <sally@sally.com>
EOS

    assert_equal "Bob <bob@bob.com>", h["From"]
    assert_equal "Sally <sally@sally.com>", h["To"]
    assert_nil h["Message-Id"]
  end

  ## this is shitty behavior in retrospect, but it's built in now.
  def test_message_id_stripping
    h = MBox.read_header StringIO.new("Message-Id: <one@bob.com>\n")
    assert_equal "one@bob.com", h["Message-Id"]

    h = MBox.read_header StringIO.new("Message-Id: one@bob.com\n")
    assert_equal "one@bob.com", h["Message-Id"]
  end

  def test_multiline
    h = MBox.read_header StringIO.new(<<EOS)
From: Bob <bob@bob.com>
Subject: one two three
  four five six
To: Sally <sally@sally.com>
References: seven
  eight
Seven: Eight
EOS

    assert_equal "one two three four five six", h["Subject"]
    assert_equal "Sally <sally@sally.com>", h["To"]
    assert_equal "seven eight", h["References"]
  end

  def test_ignore_spacing
    variants = [
      "Subject:one two  three   end\n",
      "Subject:    one two  three   end\n",
      "Subject:   one two  three   end    \n",
    ]
    variants.each do |s|
      h = MBox.read_header StringIO.new(s)
      assert_equal "one two  three   end", h["Subject"]
    end
  end

  def test_message_id_ignore_spacing
    variants = [
      "Message-Id:     <one@bob.com>       \n",
      "Message-Id:      one@bob.com        \n",
      "Message-Id:<one@bob.com>       \n",
      "Message-Id:one@bob.com       \n",
    ]
    variants.each do |s|
      h = MBox.read_header StringIO.new(s)
      assert_equal "one@bob.com", h["Message-Id"]
    end
  end

  def test_ignore_empty_lines
    variants = [
      "",
      "Message-Id:       \n",
      "Message-Id:\n",
    ]
    variants.each do |s|
      h = MBox.read_header StringIO.new(s)
      assert_nil h["Message-Id"]
    end
  end

  def test_detect_end_of_headers
    h = MBox.read_header StringIO.new(<<EOS)
From: Bob <bob@bob.com>

To: a dear friend
EOS
  assert_equal "Bob <bob@bob.com>", h["From"]
  assert_nil h["To"]

  h = MBox.read_header StringIO.new(<<EOS)
From: Bob <bob@bob.com>
\r
To: a dear friend
EOS
  assert_equal "Bob <bob@bob.com>", h["From"]
  assert_nil h["To"]

  h = MBox.read_header StringIO.new(<<EOS)
From: Bob <bob@bob.com>
\r\n\r
To: a dear friend
EOS
  assert_equal "Bob <bob@bob.com>", h["From"]
  assert_nil h["To"]
  end
end
