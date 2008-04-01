module Redwood

class LabelListMode < LineCursorMode
  register_keymap do |k|
    k.add :select_label, "Search by label", :enter
    k.add :reload, "Discard label list and reload", '@'
    k.add :jump_to_next_new, "Jump to next new thread", :tab
    k.add :toggle_show_unread_only, "Toggle between showing all labels and those with unread mail", 'u'
  end

  def initialize
    @labels = []
    @text = []
    @unread_only = false
    super
    regen_text
  end

  def lines; @text.length end
  def [] i; @text[i] end

  def jump_to_next_new
    n = ((curpos + 1) ... lines).find { |i| @labels[i][1] > 0 } || (0 ... curpos).find { |i| @labels[i][1] > 0 }
    if n
      ## jump there if necessary
      jump_to_line n unless n >= topline && n < botline
      set_cursor_pos n
    else
      BufferManager.flash "No labels messages with unread messages."
    end
  end

  def focus
    reload # make sure unread message counts are up-to-date
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
    labels = LabelManager.listable_labels

    counts = labels.map do |label|
      string = LabelManager.string_for label
      total = Index.num_results_for :label => label
      unread = Index.num_results_for :labels => [label, :unread]
      [label, string, total, unread]
    end.sort_by { |l, s, t, u| s.downcase }

    width = counts.max_of { |l, s, t, u| s.length }

    if @unread_only
      counts.delete_if { | l, s, t, u | u == 0 }
    end

    @labels = []
    counts.map do |label, string, total, unread|
      if total == 0 && !LabelManager::RESERVED_LABELS.include?(label)
        Redwood::log "no hits for label #{label}, deleting"
        LabelManager.delete label
        next
      end

      @text << [[(unread == 0 ? :labellist_old_color : :labellist_new_color),
          sprintf("%#{width + 1}s %5d %s, %5d unread", string, total, total == 1 ? " message" : "messages", unread)]]
      @labels << [label, unread]
      yield i if block_given?
    end.compact

    BufferManager.flash "No labels with unread messages!" if counts.empty? && @unread_only
  end

  def select_label
    label, num_unread = @labels[curpos]
    return unless label
    LabelSearchResultsMode.spawn_nicely label
  end
end

end
