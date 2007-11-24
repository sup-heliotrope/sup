module Redwood

class LabelSearchResultsMode < ThreadIndexMode
  def initialize labels
    @labels = labels
    opts = { :labels => @labels }
    opts[:load_deleted] = true if labels.include? :deleted
    opts[:load_spam] = true if labels.include? :spam
    super [], opts
  end

  def is_relevant? m; @labels.all? { |l| m.has_label? l }; end

  def self.spawn_nicely label
    label = LabelManager.label_for(label) unless label.is_a?(Symbol)
    case label
    when nil
    when :inbox
      BufferManager.raise_to_front InboxMode.instance.buffer
    else
      BufferManager.spawn_unless_exists("All threads with label '#{label}'") do
        mode = LabelSearchResultsMode.new([label])
        mode.load_threads :num => b.content_height
      end
    end
  end
end

end
