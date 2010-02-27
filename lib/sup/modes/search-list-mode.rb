module Redwood

class SearchListMode < LineCursorMode
  register_keymap do |k|
    k.add :select_search, "Open search results", :enter
    k.add :reload, "Discard saved search list and reload", '@'
    k.add :jump_to_next_new, "Jump to next new thread", :tab
    k.add :toggle_show_unread_only, "Toggle between showing all saved searches and those with unread mail", 'u'
    k.add :delete_selected_search, "Delete selected search", "X"
    k.add :rename_selected_search, "Rename selected search", "r"
    k.add :edit_selected_search, "Edit selected search", "e"
    k.add :add_new_search, "Add new search", "a"
  end

  HookManager.register "search-list-filter", <<EOS
Filter the search list, typically to sort.
Variables:
  counted: an array of counted searches.
Return value:
  An array of counted searches with sort_by output structure.
EOS

  HookManager.register "search-list-format", <<EOS
Create the sprintf format string for search-list-mode.
Variables:
  n_width: the maximum search name width
  tmax: the maximum total message count
  umax: the maximum unread message count
  s_width: the maximum search string width
Return value:
  A format string for sprintf
EOS

  def initialize
    @searches = []
    @text = []
    @unread_only = false
    super
    UpdateManager.register self
    regen_text
  end

  def cleanup
    UpdateManager.unregister self
    super
  end

  def lines; @text.length end
  def [] i; @text[i] end

  def jump_to_next_new
    n = ((curpos + 1) ... lines).find { |i| @searches[i][1] > 0 } || (0 ... curpos).find { |i| @searches[i][1] > 0 }
    if n
      ## jump there if necessary
      jump_to_line n unless n >= topline && n < botline
      set_cursor_pos n
    else
      BufferManager.flash "No saved searches with unread messages."
    end
  end

  def focus
    reload # make sure unread message counts are up-to-date
  end

  def handle_added_update sender, m
    reload
  end

protected

  def toggle_show_unread_only
    @unread_only = !@unread_only
    reload
  end

  def reload
    regen_text
    buffer.mark_dirty if buffer
  end

  def regen_text
    @text = []
    searches = SearchManager.all_searches

    counted = searches.map do |name|
      search_string = SearchManager.search_string_for name
      begin
        query = Index.parse_query search_string
        total = Index.num_results_for :qobj => query[:qobj]
        unread = Index.num_results_for :qobj => query[:qobj], :label => :unread
      rescue Index::ParseError => e
        BufferManager.flash "Problem: #{e.message}!"
        total = 0
        unread = 0
      end
      [name, search_string, total, unread]
    end

    if HookManager.enabled? "search-list-filter"
      counts = HookManager.run "search-list-filter", :counted => counted
    else
      counts = counted.sort_by { |n, s, t, u| n.downcase }
    end

    n_width = counts.max_of { |n, s, t, u| n.length }
    tmax    = counts.max_of { |n, s, t, u| t }
    umax    = counts.max_of { |n, s, t, u| u }
    s_width = counts.max_of { |n, s, t, u| s.length }

    if @unread_only
      counts.delete_if { | n, s, t, u | u == 0 }
    end

    @searches = []
    counts.each do |name, search_string, total, unread|
      fmt = HookManager.run "search-list-format", :n_width => n_width, :tmax => tmax, :umax => umax, :s_width => s_width
      if !fmt
        fmt = "%#{n_width + 1}s %5d %s, %5d unread: %s"
      end
      @text << [[(unread == 0 ? :labellist_old_color : :labellist_new_color),
          sprintf(fmt, name, total, total == 1 ? " message" : "messages", unread, search_string)]]
      @searches << [name, unread]
    end

    BufferManager.flash "No saved searches with unread messages!" if counts.empty? && @unread_only
  end

  def select_search
    name, num_unread = @searches[curpos]
    return unless name
    SearchResultsMode.spawn_from_query SearchManager.search_string_for(name)
  end

  def delete_selected_search
    name, num_unread = @searches[curpos]
    return unless name
    reload if SearchManager.delete name
  end

  def rename_selected_search
    old_name, num_unread = @searches[curpos]
    return unless old_name
    new_name = BufferManager.ask :save_search, "Rename this saved search: ", old_name
    return unless new_name && new_name !~ /^\s*$/ && new_name != old_name
    new_name.strip!
    unless SearchManager.valid_name? new_name
      BufferManager.flash "Not renamed: " + SearchManager.name_format_hint
      return
    end
    if SearchManager.all_searches.include? new_name
      BufferManager.flash "Not renamed: \"#{new_name}\" already exists"
      return
    end
    reload if SearchManager.rename old_name, new_name
    set_cursor_pos @searches.index([new_name, num_unread])||curpos
  end

  def edit_selected_search
    name, num_unread = @searches[curpos]
    return unless name
    old_search_string = SearchManager.search_string_for name
    new_search_string = BufferManager.ask :search, "Edit this saved search: ", (old_search_string + " ")
    return unless new_search_string && new_search_string !~ /^\s*$/ && new_search_string != old_search_string
    reload if SearchManager.edit name, new_search_string.strip
    set_cursor_pos @searches.index([name, num_unread])||curpos
  end

  def add_new_search
    search_string = BufferManager.ask :search, "New search: "
    return unless search_string && search_string !~ /^\s*$/
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
    reload if SearchManager.add name, search_string.strip
    set_cursor_pos @searches.index(@searches.assoc(name))||curpos
  end
end

end
