require "sup"
require "test_helper"

class TestIndexIntegration < Minitest::Test
  include Redwood

  def setup
    @path = Dir.mktmpdir
  end

  def teardown
    ObjectSpace.each_object(Class).select {|a| a < Redwood::Singleton}.each do |klass|
      klass.deinstantiate! unless klass == Redwood::Logger
    end
    FileUtils.rm_r @path
  end

  def create_large_mbox n_messages
    mbox = File.join @path, "big.mbox"
    File.open(mbox, "w") do |f|
      n_messages.times do |i|
        ## spread the dates out so that the assigned docids are not
        ## contiguous, as in a real index
        date = Time.utc(2011) + i * 3600
        f.write <<EOS
From bob@example.com Sat Jan  1 00:00:00 2011
From: Bob <bob@example.com>
To: Joe <joe@example.com>
Subject: message number #{i}
Date: #{date.strftime "%a, %d %b %Y %H:%M:%S +0000"}
Message-ID: <message-#{i}@example.com>

Hi Bob, this is test message #{i}. From Joe.

EOS
      end
    end
    mbox
  end

  def start_sup_and_add_source source
    start
    Logger.remove_sink $stderr
    Index.init @path
    Index.load
    SourceManager.instance.instance_eval '@sources = {}'
    SourceManager.instance.add_source source
    PollManager.poll_from source
    Index.save_index
  end

  def test_all_mail_query
    n_messages = 1200
    mbox = create_large_mbox n_messages
    start_sup_and_add_source MBox.new "mbox:#{mbox}"

    ## the empty query is the "all mail" listing
    ids = []
    Index.each_id({}) { |id| ids << id }
    assert_equal n_messages, ids.size
  end
end
