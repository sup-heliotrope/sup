require "sup/modes/thread_index_mode"

module Redwood

class InboxMode < ThreadIndexMode
  register_keymap do |k|
    ## overwrite toggle_archived with archive
    k.add :archive, "Archive thread (remove from inbox)", 'a'
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
      Index.save_thread thread
    end

    cursor_thread.remove_label :inbox
    hide_thread cursor_thread
    regen_text
    Index.save_thread thread
  end

  def multi_archive threads
    UndoManager.register "archiving #{threads.size.pluralize 'thread'}" do
      threads.map do |t|
        t.apply_label :inbox
        add_or_unhide t.first
        Index.save_thread t
      end
      regen_text
    end

    threads.each do |t|
      t.remove_label :inbox
      hide_thread t
    end
    regen_text
    threads.each { |t| Index.save_thread t }
  end

  def handle_unarchived_update sender, m
    add_or_unhide m
  end

  def handle_archived_update sender, m
    t = thread_containing(m) or return
    hide_thread t
    regen_text
  end

  def handle_idle_update sender, idle_since
    flush_index
  end

  def status
    starred = Index.num_results_for(:labels => [:starred])
    unread = Index.num_results_for(:labels => [:unread])
    super + "    #{Index.size} messages in index (#{starred} starred, #{unread} unread)"
  end
end

end
