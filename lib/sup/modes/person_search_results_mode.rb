module Redwood

class PersonSearchResultsMode < ThreadIndexMode
  def initialize people
    @people = people
    super [], { :participants => @people }
  end

  def is_relevant? m; @people.any? { |p| m.from == p }; end
end

end
