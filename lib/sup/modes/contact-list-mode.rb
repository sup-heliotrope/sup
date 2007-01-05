module Redwood

class ContactListMode < LineCursorMode
  LOAD_MORE_CONTACTS_NUM = 10

  register_keymap do |k|
    k.add :load_more, "Load #{LOAD_MORE_CONTACTS_NUM} more contacts", 'M'
    k.add :reload, "Reload contacts", 'R'
    k.add :alias, "Edit alias for contact", 'a'
    k.add :toggle_tagged, "Tag/untag current line", 't'
    k.add :apply_to_tagged, "Apply next command to all tagged items", ';'
    k.add :search, "Search for messages from particular people", 'S'
  end

  def initialize mode = :regular
    @mode = mode
    @tags = Tagger.new self
    @num = 0
    super()
  end

  def lines; @text.length; end
  def [] i; @text[i]; end

  def toggle_tagged
    p = @contacts[curpos] or return
    @tags.toggle_tag_for p
    update_text_for_line curpos
    cursor_down
  end

  def multi_toggle_tagged threads
    @tags.drop_all_tags
    regen_text
  end

  def apply_to_tagged; @tags.apply_to_tagged; end

  def load; regen_text; end
  def load_more num=LOAD_MORE_CONTACTS_NUM
    @num += num
    regen_text
    BufferManager.flash "Added #{num} contacts."
  end

  def multi_select people
    case @mode
    when :regular
      mode = ComposeMode.new :to => people
      BufferManager.spawn "new message", mode
      mode.edit
    end
  end

  def select
    p = @contacts[curpos] or return
    multi_select [p]
  end

  def multi_search people
    mode = PersonSearchResultsMode.new people
    BufferManager.spawn "personal search results", mode
    mode.load_threads :num => mode.buffer.content_height
  end

  def search
    p = @contacts[curpos] or return
    multi_search [p]
  end    

  def reload
    @tags.drop_all_tags
    load
  end

  def alias
    p = @contacts[curpos] or return
    a = BufferManager.ask(:alias, "alias for #{p.longname}: ", @user_contacts[p]) or return
    if a.empty?
      ContactManager.drop_contact p
    else
      ContactManager.set_contact p, a
      @user_contacts[p] = a
      update_text_for_line curpos
    end
  end

protected

  def update_text_for_line line
    @text[line] = text_for_contact @contacts[line]
    buffer.mark_dirty
  end

  def text_for_contact p
    aalias = @user_contacts[p] || ""
    [[:tagged_color, @tags.tagged?(p) ? ">" : " "],
     [:none, sprintf("%-#{@awidth}s %-#{@nwidth}s %s", aalias, p.name, p.email)]]
  end

  def regen_text
    @user_contacts = ContactManager.contacts.invert
    recent = Index.load_contacts AccountManager.user_emails,
                                 :num => @num
    
    @contacts = (@user_contacts.keys + recent.select { |p| !@user_contacts[p] }).sort_by { |p| p.sort_by_me + (p.name || "") + p.email }.remove_successive_dupes

    @awidth, @nwidth = 0, 0
    @contacts.each do |p|
      aalias = @user_contacts[p]
      @awidth = aalias.length if aalias && aalias.length > @awidth
      @nwidth = p.name.length if p.name && p.name.length > @nwidth
    end

    @text = @contacts.map { |p| text_for_contact p }
    buffer.mark_dirty if buffer
  end
end

end
