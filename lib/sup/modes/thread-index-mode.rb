module Redwood

## subclasses should implement load_threads

class ThreadIndexMode < LineCursorMode
  DATE_WIDTH = Time::TO_NICE_S_MAX_LEN
  FROM_WIDTH = 15
  LOAD_MORE_THREAD_NUM = 20

  register_keymap do |k|
    k.add :load_threads, "Load #{LOAD_MORE_THREAD_NUM} more threads", 'M'
    k.add :reload, "Discard threads and reload", 'D'
    k.add :toggle_archived, "Toggle archived status", 'a'
    k.add :toggle_starred, "Star or unstar all messages in thread", '*'
    k.add :toggle_new, "Toggle new/read status of all messages in thread", 'N'
    k.add :edit_labels, "Edit or add labels for a thread", 'l'
    k.add :edit_message, "Edit message (drafts only)", 'e'
    k.add :mark_as_spam, "Mark thread as spam", 'S'
    k.add :kill, "Kill thread (never to be seen in inbox again)", '&'
    k.add :save, "Save changes now", '$'
    k.add :jump_to_next_new, "Jump to next new thread", :tab
    k.add :reply, "Reply to a thread", 'r'
    k.add :forward, "Forward a thread", 'f'
    k.add :toggle_tagged, "Tag/untag current line", 't'
    k.add :apply_to_tagged, "Apply next command to all tagged threads", ';'
  end

  def initialize required_labels=[], hidden_labels=[]
    super()
    @load_thread = nil
    @required_labels = required_labels
    @hidden_labels = hidden_labels + LabelManager::HIDDEN_LABELS
    @date_width = DATE_WIDTH
    @from_width = FROM_WIDTH
    @size_width = nil

    @tags = Tagger.new self
    
    initialize_threads
    update

    UpdateManager.register self
  end

  def lines; @text.length; end
  def [] i; @text[i]; end

  def reload
    drop_all_threads
    BufferManager.draw_screen
    load_threads :num => buffer.content_height
  end

  ## open up a thread view window
  def select t=nil
    t ||= @threads[curpos]

    ## TODO: don't regen text completely
    Redwood::reporting_thread do
      mode = ThreadViewMode.new t, @hidden_labels
      BufferManager.spawn t.subj, mode
      BufferManager.draw_screen
    end
  end

  def multi_select threads
    threads.each { |t| select t }
  end
  
  def handle_starred_update m
    return unless(t = @ts.thread_for m)
    @starred_cache[t] = t.has_label? :starred
    update_text_for_line @lines[t]
  end

  def handle_read_update m
    return unless(t = @ts.thread_for m)
    @new_cache[t] = false
    update_text_for_line @lines[t]
  end

  ## overwrite me!
  def is_relevant? m; false; end

  def handle_add_update m
    if is_relevant?(m) || @ts.is_relevant?(m)
      @ts.load_thread_for_message m
      @new_cache.delete @ts.thread_for(m) # force recalculation of newness
      update
    end
  end

  def handle_delete_update mid
    if @ts.contains_id? mid
      @ts.remove mid
      update
    end
  end

  def update
    ## let's see you do THIS in python
    @threads = @ts.threads.select { |t| !@hidden_threads[t] }.sort_by { |t| t.date }.reverse
    @size_width = (@threads.map { |t| t.size }.max || 0).num_digits
    regen_text
  end

  def edit_message
    t = @threads[curpos] or return
    message, *crap = t.find { |m, *o| m.has_label? :draft }
    if message
      mode = ResumeMode.new message
      BufferManager.spawn "Edit message", mode
    else
      BufferManager.flash "Not a draft message!"
    end
  end

  def toggle_starred
    t = @threads[curpos] or return
    @starred_cache[t] = t.toggle_label :starred
    update_text_for_line curpos
    cursor_down
  end

  def multi_toggle_starred threads
    threads.each { |t| @starred_cache[t] = t.toggle_label :starred }
    regen_text
  end

  def toggle_archived
    return unless(t = @threads[curpos])
    t.toggle_label :inbox
    update_text_for_line curpos
    cursor_down
  end

  def multi_toggle_archived threads
    threads.each { |t| t.toggle_label :inbox }
    regen_text
  end

  def toggle_new
    t = @threads[curpos] or return
    @new_cache[t] = t.toggle_label :unread
    update_text_for_line curpos
    cursor_down
  end

  def multi_toggle_new threads
    threads.each { |t| @new_cache[t] = t.toggle_label :unread }
    regen_text
  end

  def multi_toggle_tagged threads
    @tags.drop_all_tags
    regen_text
  end

  def jump_to_next_new
    t = @threads[curpos] or return
    n = ((curpos + 1) .. lines).find { |i| @new_cache[@threads[i]] }
    n = (0 ... curpos).find { |i| @new_cache[@threads[i]] } unless n
    if n
      set_cursor_pos n
    else
      BufferManager.flash "No new messages"
    end
  end

  def mark_as_spam
    t = @threads[curpos] or return
    multi_mark_as_spam [t]
  end

  def multi_mark_as_spam threads
    threads.each do |t|
      t.apply_label :spam
      hide_thread t
    end
    regen_text
  end

  def kill
    t = @threads[curpos] or return
    multi_kill [t]
  end

  def multi_kill threads
    threads.each do |t|
      t.apply_label :killed
      hide_thread t
    end
    regen_text
  end

  def save
    threads = @threads + @hidden_threads.keys

    BufferManager.say("Saving threads...") do |say_id|
      threads.each_with_index do |t, i|
        next unless t.dirty?
        BufferManager.say "Saving thread #{i +1} of #{threads.length}...", say_id
        t.save Index
      end
    end
  end

  def cleanup
    UpdateManager.unregister self

    if @load_thread
      @load_thread.kill 
      BufferManager.clear @mbid if @mbid
      sleep 0.1 # TODO: necessary?
      BufferManager.erase_flash
    end
    save
    super
  end

  def toggle_tagged
    t = @threads[curpos] or return
    @tags.toggle_tag_for t
    update_text_for_line curpos
    cursor_down
  end

  def apply_to_tagged; @tags.apply_to_tagged; end

  def edit_labels
    thread = @threads[curpos]
    speciall = (@hidden_labels + LabelManager::RESERVED_LABELS).uniq
    keepl, modifyl = thread.labels.partition { |t| speciall.member? t }
    label_string = modifyl.join(" ")

    answer = BufferManager.ask :edit_labels, "edit labels: ", label_string
    return unless answer
    user_labels = answer.split(/\s+/).map { |l| l.intern }
    
    hl = user_labels.select { |l| speciall.member? l }
    if hl.empty?
      thread.labels = keepl + user_labels
      user_labels.each { |l| LabelManager << l }
    else
      BufferManager.flash "'#{hl}' is a reserved label!"
    end
    update_text_for_line curpos
  end

  def multi_edit_labels threads
    answer = BufferManager.ask :add_labels, "add labels: "
    return unless answer
    user_labels = answer.split(/\s+/).map { |l| l.intern }
    
    hl = user_labels.select { |l| @hidden_labels.member? l }
    if hl.empty?
      threads.each { |t| user_labels.each { |l| t.apply_label l } }
      user_labels.each { |l| LabelManager << l }
    else
      BufferManager.flash "'#{hl}' is a reserved label!"
    end
    regen_text
  end

  def reply
    t = @threads[curpos] or return
    m = t.latest_message
    return if m.nil? # probably won't happen
    mode = ReplyMode.new m
    BufferManager.spawn "Reply to #{m.subj}", mode
  end

  def forward
    t = @threads[curpos] or return
    m = t.latest_message
    return if m.nil? # probably won't happen
    mode = ForwardMode.new m
    BufferManager.spawn "Forward of #{m.subj}", mode
    mode.edit
  end

  def load_n_threads_background n=LOAD_MORE_THREAD_NUM, opts={}
    return if @load_thread
    @load_thread = Redwood::reporting_thread do 
      num = load_n_threads n, opts
      opts[:when_done].call(num) if opts[:when_done]
      @load_thread = nil
    end
  end

  def load_n_threads n=LOAD_MORE_THREAD_NUM, opts={}
    @mbid = BufferManager.say "Searching for threads..."
    orig_size = @ts.size
    @ts.load_n_threads(@ts.size + n, opts) do |i|
      BufferManager.say "Loaded #{i} threads...", @mbid
      if i % 5 == 0
        update
        BufferManager.draw_screen
      end
    end
    @ts.threads.each { |th| th.labels.each { |l| LabelManager << l } }

    update
    BufferManager.clear @mbid
    @mbid = nil
    BufferManager.draw_screen
    @ts.size - orig_size
  end

  def status
    "line #{curpos + 1} of #{lines} #{dirty? ? '*modified*' : ''}"
  end

protected

  def cursor_thread; @threads[curpos]; end

  def drop_all_threads
    @tags.drop_all_tags
    initialize_threads
    update
  end

  def remove_label_and_hide_thread t, label
    t.remove_label label
    hide_thread t
  end

  def hide_thread t
    raise "already hidden" if @hidden_threads[t]
    @hidden_threads[t] = true
    @threads.delete t
    @tags.drop_tag_for t
  end

  def update_text_for_line l
    return unless l # not sure why this happens, but it does, occasionally
    @text[l] = text_for_thread @threads[l]
    buffer.mark_dirty if buffer
  end

  def regen_text
    @text = @threads.map_with_index { |t, i| text_for_thread t }
    @lines = @threads.map_with_index { |t, i| [t, i] }.to_h
    buffer.mark_dirty if buffer
  end
  
  def author_text_for_thread t
    if t.authors.size == 1
      t.authors.first.mediumname
    else
      t.authors.map { |p| AccountManager.is_account?(p) ? "me" : p.shortname }.join ", "
    end
  end

  def text_for_thread t
    date = (@date_cache[t] ||= t.date.to_nice_s(Time.now)) 
    from = (@who_cache[t] ||= author_text_for_thread(t))
    if from.length > @from_width
      from = from[0 ... (@from_width - 1)]
      from += "." unless from[-1] == ?\s
    end

    new = @new_cache.member?(t) ? @new_cache[t] : @new_cache[t] = t.has_label?(:unread)
    starred = @starred_cache.member?(t) ? @starred_cache[t] : @starred_cache[t] = t.has_label?(:starred)

    dp = (@dp_cache[t] ||= t.direct_participants.any? { |p| AccountManager.is_account? p })
    p = (@p_cache[t] ||= (dp || t.participants.any? { |p| AccountManager.is_account? p }))

    base_color = (new ? :index_new_color : :index_old_color)
    [ 
      [:tagged_color, @tags.tagged?(t) ? ">" : " "],
      [:none, sprintf("%#{@date_width}s ", date)],
      [base_color, sprintf("%-#{@from_width}s", from)],
      [:starred_color, starred ? "*" : " "],
      [:none, t.size == 1 ? " " * (@size_width + 2) : sprintf("(%#{@size_width}d)", t.size)],
      [:to_me_color, dp ? " >" : (p ? ' +' : "  ")],
      [base_color, t.subj + (t.subj.empty? ? "" : " ")],
    ] +
      (t.labels - @hidden_labels).map { |label| [:label_color, "+#{label} "] } +
      [[:snippet_color, t.snippet]
    ]
  end

  def dirty?; (@hidden_threads.keys + @threads).any? { |t| t.dirty? }; end

private

  def initialize_threads
    @ts = ThreadSet.new Index.instance
    @date_cache = {}
    @who_cache = {}
    @dp_cache = {}
    @p_cache = {}
    @new_cache = {}
    @starred_cache = {}
    @hidden_threads = {}
  end
end

end
