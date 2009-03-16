require 'thread'

module Redwood

class InboxMode < ThreadIndexMode
  register_keymap do |k|
    ## overwrite toggle_archived with archive
    k.add :archive, "Archive thread (remove from inbox)", 'a'
    k.add :read_and_archive, "Archive thread (remove from inbox) and mark read", 'A'
  end

  def initialize
    super [:inbox, :sent, :draft], { :label => :inbox, :skip_killed => true }
    raise "can't have more than one!" if defined? @@instance
    @@instance = self
  end

  def is_relevant? m
    m.has_label?(:inbox) && ([:spam, :deleted, :killed] & m.labels).empty?
  end

  ## label-list-mode wants to be able to raise us if the user selects
  ## the "inbox" label, so we need to keep our singletonness around
  def self.instance; @@instance; end
  def killable?; false; end

  def archive
    return unless cursor_thread
    thread = cursor_thread # to make sure lambda only knows about 'old' cursor_thread

    undo = lambda {
      thread.apply_label :inbox
      add_or_unhide thread.first
    }
    UndoManager.register("archiving thread #{thread.first.id}", undo)

    cursor_thread.remove_label :inbox
    hide_thread cursor_thread
    regen_text
  end

  def multi_archive threads
    undo = threads.map {|t|
             lambda{
               t.apply_label :inbox
               add_or_unhide t.first
             }}
    UndoManager.register("archiving #{threads.size} #{threads.size.pluralize 'thread'}",
                         undo << lambda {regen_text} )

    threads.each do |t|
      t.remove_label :inbox
      hide_thread t
    end
    regen_text
  end

  def read_and_archive
    return unless cursor_thread
    thread = cursor_thread # to make sure lambda only knows about 'old' cursor_thread

    undo = lambda {
      thread.apply_label :inbox
      thread.apply_label :unread
      add_or_unhide thread.first
    }
    UndoManager.register("reading and archiving thread ", undo)

    cursor_thread.remove_label :unread
    cursor_thread.remove_label :inbox
    hide_thread cursor_thread
    regen_text
  end

  def multi_read_and_archive threads
    undo = threads.map {|t|
      lambda {
        t.apply_label :inbox
        t.apply_label :unread
        add_or_unhide t.first
      }
    }
    UndoManager.register("reading and archiving #{threads.size} #{threads.size.pluralize 'thread'}",
                         undo << lambda {regen_text})

    threads.each do |t|
      t.remove_label :unread
      t.remove_label :inbox
      hide_thread t
    end
    regen_text
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
