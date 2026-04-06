require "minitest/mock"
require "test_helper"

require "sup"

class TestIndex < Minitest::Test
  def setup
    @path = Dir.mktmpdir
    Redwood::start
    Redwood::Logger.remove_sink $stderr
    Redwood::Index.init @path
    Redwood::Index.load
  end

  def teardown
    Redwood::Index.save_index
    ObjectSpace.each_object(Class).select {|a| a < Redwood::Singleton}.each do |klass|
      klass.deinstantiate! unless klass == Redwood::Logger
    end
    FileUtils.rm_r @path
  end

  def with_fake_time &block
    Time.stub :now, Time.utc(2000) do
      ## Also stub Time.local to behave like Time.utc so that Chronic.parse
      ## doesn't pick up the timezone of the test runner.
      Time.stub :local, ->(*args) { Time.utc(*args) }, &block
    end
  end

  def test_date_query_parsing
    parsed = with_fake_time do
      Redwood::Index.parse_query "after:yesterday"
    end
    expected_qobj = Xapian::Query.new(
      Xapian::Query::OP_VALUE_RANGE,
      Redwood::Index::DATE_VALUENO,
      Xapian.sortable_serialise(Time.utc(2000, 1, 1).to_i),
      Xapian.sortable_serialise(2**32),
    )
    assert_equal expected_qobj.description, parsed[:qobj].description

    parsed = with_fake_time do
      Redwood::Index.parse_query "before:yesterday"
    end
    expected_qobj = Xapian::Query.new(
      Xapian::Query::OP_VALUE_RANGE,
      Redwood::Index::DATE_VALUENO,
      Xapian.sortable_serialise(0),
      Xapian.sortable_serialise(Time.utc(2000, 1, 1).to_i),
    )
    assert_equal expected_qobj.description, parsed[:qobj].description

    parsed = with_fake_time do
      Redwood::Index.parse_query "during:yesterday"
    end
    expected_qobj = Xapian::Query.new(
      Xapian::Query::OP_VALUE_RANGE,
      Redwood::Index::DATE_VALUENO,
      Xapian.sortable_serialise(Time.utc(1999, 12, 31).to_i),
      Xapian.sortable_serialise(Time.utc(2000,  1,  1).to_i),
    )
    assert_equal expected_qobj.description, parsed[:qobj].description
  end
end
