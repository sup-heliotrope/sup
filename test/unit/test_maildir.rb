require 'test_helper'
require 'sup'
require 'sup/maildir'

module Redwood

class TestMaildir < Minitest::Test
  def test_flag_parsing
    maildir = Maildir.new "maildir:/nowhere"
    labels = maildir.labels? "asdf:2,S"
    assert_equal [], labels
    labels = maildir.labels? "asdf:2,"
    assert_equal [:unread], labels
    labels = maildir.labels? "asdf:2,DFPRST"
    assert_equal [:deleted, :starred, :forwarded, :replied, :draft], labels
    labels = maildir.labels? "asdf:2,DFPRT"
    assert_equal [:unread, :deleted, :starred, :forwarded, :replied, :draft], labels
  end
end

end
