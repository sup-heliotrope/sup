require "test_helper.rb"

require "sup/util/uri"

describe Redwood::Util::Uri do
  describe ".build" do
    it "builds uri from hash" do
      components = {:path => "/var/mail/foo", :scheme => "mbox"}
      uri = Redwood::Util::Uri.build(components)
      uri.to_s.must_equal "mbox:/var/mail/foo"
    end

    it "expands ~ in path" do
      components = {:path => "~/foo", :scheme => "maildir"}
      uri = Redwood::Util::Uri.build(components)
      uri.to_s.must_equal "maildir:#{ENV["HOME"]}/foo"
    end
  end
end
