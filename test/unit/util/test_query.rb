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
  end
end
