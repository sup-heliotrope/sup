require "test_helper.rb"

require "sup/util/uri"

describe Redwood::Util::Uri do
  describe ".build" do
    it "builds uri from hash" do
      components = {:path => "/var/mail/foo", :scheme => "mbox"}
      uri = Redwood::Util::Uri.build(components)
      assert_equal "mbox:/var/mail/foo", uri.to_s
    end

    it "expands ~ in path" do
      components = {:path => "~/foo", :scheme => "maildir"}
      uri = Redwood::Util::Uri.build(components)
      assert_equal "maildir:#{ENV["HOME"]}/foo", uri.to_s
    end
  end
end
