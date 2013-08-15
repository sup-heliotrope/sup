require "test_helper"

require "sup/service/label_service"

require "tmpdir"

describe Redwood::LabelService do
  let(:tmpdir) { Dir.mktmpdir }
  after do
    require "fileutils"
    FileUtils.remove_entry_secure @tmpdir unless @tmpdir.nil?
  end

  describe "#add_labels" do
    # Integration tests are hard to write at this moment :(
    it "add labels to all messages matching the query"
  end
end
