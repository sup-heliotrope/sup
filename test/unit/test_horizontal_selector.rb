require "test_helper" 

require "sup/horizontal_selector"

describe Redwood::HorizontalSelector do
  let(:values) { %w[foo@example.com bar@example.com] }
  let(:strange_value) { "strange@example.com" }

  before do
    @selector = Redwood::HorizontalSelector.new(
      'Acc:', values, [])
  end

  it "init w/ the first value selected" do
    first_value = values.first
    @selector.val.must_equal first_value
  end

  it "stores value for selection" do
    second_value = values[1]
    @selector.set_to second_value
    @selector.val.must_equal second_value
  end

  describe "for unknown value" do
    it "cannot select unknown value" do
      @selector.wont_be :can_set_to?, strange_value
    end

    it "refuses selecting unknown value" do
      old_value = @selector.val

      assert_raises Redwood::HorizontalSelector::UnknownValue do
        @selector.set_to strange_value
      end

      @selector.val.must_equal old_value
    end
  end
end
