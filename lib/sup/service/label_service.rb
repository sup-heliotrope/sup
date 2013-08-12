require "sup/index"

module Redwood
  # Provides label tweaking service to the user.
  # Working as the backend of ConsoleMode.
  #
  # Should become the backend of bin/sup-tweak-labels in the future.
  class LabelService
    # @param index [Redwood::Index]
    def initialize index=Index.instance
      @index = index
    end

    def add_labels query, *labels
      run_on_each_message(query) do |m|
        labels.each {|l| m.add_label l }
      end
    end

    def remove_labels query, *labels
      run_on_each_message(query) do |m|
        labels.each {|l| m.remove_label l }
      end
    end


    private
    def run_on_each_message query, &operation
      count = 0

      find_messages(query).each do |m|
        operation.call(m)
        @index.update_message_state m
        count += 1
      end

      @index.save_index
      count
    end

    def find_messages query
      @index.find_messages(query)
    end
  end
end
