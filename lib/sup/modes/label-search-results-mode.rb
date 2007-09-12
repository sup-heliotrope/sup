module Redwood

class LabelSearchResultsMode < ThreadIndexMode
  def initialize labels
    @labels = labels
    opts = { :labels => @labels }
    opts[:load_killed] = true if labels.include? :killed
    opts[:load_deleted] = true if labels.include? :deleted
    opts[:load_spam] = true if labels.include? :spam
    super [], opts
  end

  def is_relevant? m; @labels.all? { |l| m.has_label? l }; end
end

end
