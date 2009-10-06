module Redwood

module CanAliasContacts
  include M17n

  def alias_contact p
    aalias = BufferManager.ask(:alias, m('contact_list.ask.alias_for', :name => p.longname), ContactManager.alias_for(p))
    return if aalias.nil?
    aalias = nil if aalias.empty? # allow empty aliases

    name = BufferManager.ask(:name, m('contact_list.ask.name_for', :name => p.longname), p.name)
    return if name.nil? || name.empty? # don't allow empty names
    p.name = name

    ContactManager.update_alias p, aalias
    BufferManager.flash m('flash.info.contact_updated')
  end
end

class ContactListMode < LineCursorMode
  include M17n

  LOAD_MORE_CONTACTS_NUM = 10

  register_keymap do |k|
    km = m('contact_list.keymap')
    k.add :load_more, m('contact_list.keymap.load_more', :num => LOAD_MORE_CONTACTS_NUM), 'M'
    k.add :reload, km['reload'], 'D'
    k.add :alias, km['alias'], 'a', 'i'
    k.add :toggle_tagged, km['toggle_tagged'], 't'
    k.add :apply_to_tagged, km['apply_to_tagged'], '+'
    k.add :search, km['search'], 'S'
  end

  def initialize mode=:regular
    @mode = mode
    @tags = Tagger.new self, "contact"
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
    BufferManager.flash "Added #{num.pluralize 'contact'}."
  end

  def multi_select people
    case @mode
    when :regular
      mode = ComposeMode.new :to => people
      BufferManager.spawn "new message", mode
      mode.edit_message
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
    Redwood::reporting_thread("contact manager load in bg") do
      load
      update
      BufferManager.draw_screen
    end
  end

  def load
    @num ||= buffer.content_height
    @user_contacts = ContactManager.contacts_with_aliases
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
