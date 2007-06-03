module Redwood

class LabelSearchResultsMode < ThreadIndexMode
  def initialize labels
    @labels = labels
    super [], { :labels => @labels }
  end

  def is_relevant? m; @labels.all? { |l| m.has_label? l }; end
end

end
