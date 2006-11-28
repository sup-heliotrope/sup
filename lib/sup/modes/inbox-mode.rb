require 'thread'

module Redwood

class InboxMode < ThreadIndexMode
  register_keymap do |k|
    ## overwrite toggle_archived with archive
    k.add :archive, "Archive thread (remove from inbox)", 'a'
    k.add :load_more_threads, "Load #{LOAD_MORE_THREAD_NUM} more threads", 'M'
    k.add :reload, "Discard threads and reload", 'R'
  end

  def initialize
    super [:inbox], [:inbox]
  end

  def archive
    remove_label_and_hide_thread cursor_thread, :inbox
    regen_text
  end

  def multi_archive threads
    threads.each { |t| remove_label_and_hide_thread t, :inbox }
    regen_text
  end

  def is_relevant? m; m.has_label? :inbox; end

  def load_more_threads n=ThreadIndexMode::LOAD_MORE_THREAD_NUM
    load_n_threads_background n, :label => :inbox,
                                 :load_killed => false,
                                 :load_spam => false,
                                 :when_done => lambda { |num|
      BufferManager.flash "Added #{num} threads."
    }
  end

  def reload
    drop_all_threads
    BufferManager.draw_screen
    load_more_threads buffer.content_height
  end
end

end
