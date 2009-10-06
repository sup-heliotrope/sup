require 'sup'

module Redwood

class InboxMode < ThreadIndexMode
  register_keymap do |k|
    ## overwrite toggle_archived with archive
    k.add :archive, "Archive thread (remove from inbox)", 'a'
    k.add :read_and_archive, "Archive thread (remove from inbox) and mark read", 'A'
    k.add :refine_search, "Refine search", '|'
  end

  def initialize
    super [:inbox, :sent, :draft], { :label => :inbox, :skip_killed => true }
    raise "can't have more than one!" if defined? @@instance
    @@instance = self
  end

  def is_relevant? m; (m.labels & [:spam, :deleted, :killed, :inbox]) == Set.new([:inbox]) end

  def refine_search
    text = BufferManager.ask :search, "refine inbox with query: "
    return unless text && text !~ /^\s*$/
    text = "label:inbox -label:spam -label:deleted " + text
    SearchResultsMode.spawn_from_query text
  end

  ## label-list-mode wants to be able to raise us if the user selects
  ## the "inbox" label, so we need to keep our singletonness around
  def self.instance; @@instance; end
  def killable?; false; end

  def archive
    return unless cursor_thread
    thread = cursor_thread # to make sure lambda only knows about 'old' cursor_thread

    UndoManager.register "archiving thread" do
      thread.apply_label :inbox
      add_or_unhide thread.first
    end

    cursor_thread.remove_label :inbox
    hide_thread cursor_thread
    regen_text
  end

  def multi_archive threads
    UndoManager.register "archiving #{threads.size.pluralize 'thread'}" do
      threads.map do |t|
        t.apply_label :inbox
        add_or_unhide t.first
      end
      regen_text
    end

    threads.each do |t|
      t.remove_label :inbox
      hide_thread t
    end
    regen_text
  end

  def read_and_archive
    return unless cursor_thread
    thread = cursor_thread # to make sure lambda only knows about 'old' cursor_thread

    UndoManager.register "reading and archiving thread" do
      thread.apply_label :inbox
      thread.apply_label :unread
      add_or_unhide thread.first
    end

    cursor_thread.remove_label :unread
    cursor_thread.remove_label :inbox
    hide_thread cursor_thread
    regen_text
  end

  def multi_read_and_archive threads
    old_labels = threads.map { |t| t.labels.dup }

    threads.each do |t|
      t.remove_label :unread
      t.remove_label :inbox
      hide_thread t
    end
    regen_text

    UndoManager.register "reading and archiving #{threads.size.pluralize 'thread'}" do
      threads.zip(old_labels).each do |t, l|
        t.labels = l
        add_or_unhide t.first
      end
      regen_text
    end

  end

  def handle_unarchived_update sender, m
    add_or_unhide m
  end

  def handle_archived_update sender, m
    t = thread_containing(m) or return
    hide_thread t
    regen_text
  end

  def status
    super + "    #{Index.size} messages in index"
  end
end

end
