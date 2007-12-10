require 'thread'

module Redwood

class InboxMode < ThreadIndexMode
  register_keymap do |k|
    ## overwrite toggle_archived with archive
    k.add :archive, "Archive thread (remove from inbox)", 'a'
  end

  def initialize
    super [:inbox, :sent], { :label => :inbox, :skip_killed => true }
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
    cursor_thread.remove_label :inbox
    hide_thread cursor_thread
    regen_text
  end

  def multi_archive threads
    threads.each do |t|
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
