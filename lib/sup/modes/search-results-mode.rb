module Redwood

class SearchResultsMode < ThreadIndexMode
  def initialize qobj
    @qobj = qobj
    super [], { :qobj => @qobj }
  end

  register_keymap do |k|
    k.add :refine_search, "Refine search", '.'
  end

  def refine_search
    SearchResultsMode.spawn_by_query(@qobj.to_s + " ")
  end

  ## a proper is_relevant? method requires some way of asking ferret
  ## if an in-memory object satisfies a query. i'm not sure how to do
  ## that yet. in the worst case i can make an in-memory index, add
  ## the message, and search against it to see if i have > 0 results,
  ## but that seems pretty insane.

  def self.spawn_by_query default=""
    text = BufferManager.ask :search, "query: ", default
    return unless text && text !~ /^\s*$/

    begin
      qobj = Index.parse_user_query_string text
      short_text = text.length < 20 ? text : text[0 ... 20] + "..."
      mode = SearchResultsMode.new qobj
      BufferManager.spawn "search: \"#{short_text}\"", mode
      mode.load_threads :num => mode.buffer.content_height
    rescue Ferret::QueryParser::QueryParseException => e
      BufferManager.flash "Couldn't parse query."
    end
  end
end

end
