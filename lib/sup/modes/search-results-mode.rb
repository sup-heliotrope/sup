module Redwood

class SearchResultsMode < ThreadIndexMode
  def initialize query
    @query = query
    super [], query
  end

  register_keymap do |k|
    k.add :refine_search, "Refine search", '|'
    k.add :save_search, "Save search", '%'
  end

  def refine_search
    text = BufferManager.ask :search, "refine query: ", (@query[:text] + " ")
    return unless text && text !~ /^\s*$/
    SearchResultsMode.spawn_from_query text
  end

  def save_search
    name = BufferManager.ask :save_search, "Name this search: "
    return unless name && name !~ /^\s*$/
    name.strip!
    unless SearchManager.valid_name? name
      BufferManager.flash "Not saved: " + SearchManager.name_format_hint
      return
    end
    if SearchManager.all_searches.include? name
      BufferManager.flash "Not saved: \"#{name}\" already exists"
      return
    end
    BufferManager.flash "Search saved as \"#{name}\"" if SearchManager.add name, @query[:text].strip
  end

  ## a proper is_relevant? method requires some way of asking the index
  ## if an in-memory object satisfies a query. i'm not sure how to do
  ## that yet. in the worst case i can make an in-memory index, add
  ## the message, and search against it to see if i have > 0 results,
  ## but that seems pretty insane.

  def self.spawn_from_query text
    begin
      query = Index.parse_query(text)
      return unless query
      short_text = text.length < 20 ? text : text[0 ... 20] + "..."
      mode = SearchResultsMode.new query
      BufferManager.spawn "search: \"#{short_text}\"", mode
      mode.load_threads :num => mode.buffer.content_height
    rescue Index::ParseError => e
      BufferManager.flash "Problem: #{e.message}!"
    end
  end
end

end
