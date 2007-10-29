module Redwood

class SearchResultsMode < ThreadIndexMode
  def initialize qobj
    @qobj = qobj
    super [], { :qobj => @qobj }
  end

  ## a proper is_relevant? method requires some way of asking ferret
  ## if an in-memory object satisfies a query. i'm not sure how to do
  ## that yet. in the worst case i can make an in-memory index, add
  ## the message, and search against it to see if i have > 0 results,
  ## but that seems pretty insane.

end

end
