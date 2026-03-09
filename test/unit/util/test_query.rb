# encoding: utf-8

require "test_helper"

require "sup/util/query"
require "xapian"

describe Redwood::Util::Query do
  describe ".describe" do
    it "returns a UTF-8 description of query" do
      query = Xapian::Query.new "テスト"
      life = "生活: "

      assert_raises Encoding::CompatibilityError do
        _ = life + query.description
      end

      desc = Redwood::Util::Query.describe(query)
      _ = (life + desc) # No exception thrown
    end

    it "returns a valid UTF-8 description of bad input" do
      msg = "asdfa \xc3\x28 åasdf"
      query = Xapian::Query.new msg
      life = 'hæi'

      # xapian 1.4 internally handles this bad input
      assert query.description.force_encoding("UTF-8").valid_encoding?

      assert_raises Encoding::CompatibilityError do
        _ = life + query.description
      end
    end

    it "returns a valid UTF-8 fallback description of bad input" do
      msg = "asdfa \xc3\x28 åasdf"
      query = Xapian::Query.new msg

      desc = Redwood::Util::Query.describe(query, "invalid query")

      assert desc.force_encoding("UTF-8").valid_encoding?

    end
  end
end
