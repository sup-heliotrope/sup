module Redwood

module CanAliasContacts
  def alias_contact p
    a = BufferManager.ask(:alias, "Nickname for #{p.longname}: ", ContactManager.alias_for(p)) or return
    if a.empty?
      ContactManager.drop_contact p
    else
      ContactManager.set_contact p, a
    end
  end
end

class ContactListMode < LineCursorMode
  LOAD_MORE_CONTACTS_NUM = 10

  register_keymap do |k|
    k.add :load_more, "Load #{LOAD_MORE_CONTACTS_NUM} more contacts", 'M'
    k.add :reload, "Drop contact list and reload", 'D'
    k.add :alias, "Edit nickname/alias for contact", 'a'
    k.add :toggle_tagged, "Tag/untag current line", 't'
    k.add :apply_to_tagged, "Apply next command to all tagged items", ';'
    k.add :search, "Search for messages from particular people", 'S'
  end

  def initialize mode=:regular
    @mode = mode
    @tags = Tagger.new self
    @num = nil
    @text = []
    super()
  end

  include CanAliasContacts
  def alias
    p = @contacts[curpos] or return
    alias_contact p
    update
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
    update
  end

  def apply_to_tagged; @tags.apply_to_tagged; end

  def load_more num=LOAD_MORE_CONTACTS_NUM
    @num += num
    load
    update
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
    BufferManager.spawn "search for #{people.map { |p| p.name }.join(', ')}", mode
    mode.load_threads :num => mode.buffer.content_height
  end

  def search
    p = @contacts[curpos] or return
    multi_search [p]
  end    

  def reload
    @tags.drop_all_tags
    @num = nil
    load
  end

  def load_in_background
    Redwood::reporting_thread do
      load
      update
      BufferManager.draw_screen
    end
  end

  def load
    @num ||= buffer.content_height
    @user_contacts = ContactManager.contacts
    num = [@num - @user_contacts.length, 0].max
    BufferManager.say("Loading #{num} contacts from index...") do
      recentc = Index.load_contacts AccountManager.user_emails, :num => num
      @contacts = (@user_contacts + recentc).sort_by { |p| p.sort_by_me }.uniq
    end
  end
  
protected

  def update
    regen_text
    buffer.mark_dirty if buffer
  end

  def update_text_for_line line
    @text[line] = text_for_contact @contacts[line]
    buffer.mark_dirty if buffer
  end

  def text_for_contact p
    aalias = ContactManager.alias_for(p) || ""
    [[:tagged_color, @tags.tagged?(p) ? ">" : " "],
     [:none, sprintf("%-#{@awidth}s %-#{@nwidth}s %s", aalias, p.name, p.email)]]
  end

  def regen_text
    @awidth, @nwidth = 0, 0
    @contacts.each do |p|
      aalias = ContactManager.alias_for(p)
      @awidth = aalias.length if aalias && aalias.length > @awidth
      @nwidth = p.name.length if p.name && p.name.length > @nwidth
    end

    @text = @contacts.map { |p| text_for_contact p }
  end
end

end
