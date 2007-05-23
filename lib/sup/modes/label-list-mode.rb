module Redwood

class LabelListMode < LineCursorMode
  register_keymap do |k|
    k.add :view_results, "View messages with the selected label", :enter
    k.add :reload, "Discard results and reload", 'D'
  end

  def initialize
    @labels = []
    @text = []
    super()
  end

  def lines; @text.length; end
  def [] i; @text[i]; end

  def load_in_background
    Redwood::reporting_thread do
      BufferManager.say("Counting labels...") { regen_text }
      BufferManager.draw_screen
    end
  end

protected

  def reload
    buffer.mark_dirty
    BufferManager.draw_screen
    load_in_background
  end
  
  def regen_text
    @text = []
    @labels = (LabelManager::LISTABLE_LABELS + LabelManager.user_labels).sort_by { |t| t.to_s }

    counts = @labels.map do |t|
      total = Index.num_results_for :label => t
      unread = Index.num_results_for :labels => [t, :unread]
      [t, total, unread]
    end      

    width = @labels.map { |t| t.to_s.length }.max

    counts.map_with_index do |(t, total, unread), i|
      if total == 0 && !LabelManager::LISTABLE_LABELS.include?(t)
        Redwood::log "no hits for label #{t}, deleting"
        LabelManager.delete t
        @labels.delete t
        next
      end

      label =
        case t
        when *LabelManager::LISTABLE_LABELS
          t.to_s.ucfirst
        else
          t.to_s
        end
      @text << [[(unread == 0 ? :labellist_old_color : :labellist_new_color),
          sprintf("%#{width + 1}s %5d %s, %5d unread", label, total, total == 1 ? " message" : "messages", unread)]]
      yield i if block_given?
    end.compact

    buffer.mark_dirty
  end

  def view_results
    label = @labels[curpos]
    if label == :inbox
      BufferManager.raise_to_front BufferManager["inbox"]
    else
      b = BufferManager.spawn_unless_exists("All threads with label '#{label}'") do
        mode = LabelSearchResultsMode.new [label]
      end
      b.mode.load_threads :num => b.content_height
    end
  end
end

end
