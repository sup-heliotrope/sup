require "test_helper"

require "sup/service/label_service"

describe Redwood::LabelService do
  describe "#add_labels" do
    it "add labels to all messages matching the query" do
      q = 'is:starred'
      label = 'superstarred'
      message = mock!.add_label(label).subject
      index = mock!.find_messages(q){ [message] }.subject
      mock(index).update_message_state(message)
      mock(index).save_index

      service = Redwood::LabelService.new(index)
      service.add_labels q, label
    end
  end
end
