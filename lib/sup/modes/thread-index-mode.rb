module Redwood

## subclasses should implement:
## - is_relevant?

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
    k.add :delete, "Mark thread for deletion", 'd'
    k.add :kill, "Kill thread (never to be seen in inbox again)", '&'
    k.add :save, "Save changes now", '$'
    k.add :jump_to_next_new, "Jump to next new thread", :tab
    k.add :reply, "Reply to a thread", 'r'
    k.add :forward, "Forward a thread", 'f'
    k.add :toggle_tagged, "Tag/untag current line", 't'
    k.add :apply_to_tagged, "Apply next command to all tagged threads", ';'
  end

  def initialize hidden_labels=[], load_thread_opts={}
    super()
    @mutex = Mutex.new
    @load_thread = nil
    @load_thread_opts = load_thread_opts
    @hidden_labels = hidden_labels + LabelManager::HIDDEN_LABELS
    @date_width = DATE_WIDTH
    @from_width = FROM_WIDTH
    @size_width = nil
    
    @tags = Tagger.new self
    
    initialize_threads
    update

    UpdateManager.register self

    @last_load_more_size = nil
    to_load_more do |size|
      next if @last_load_more_size == 0
      load_threads :num => 1, :background => false
      load_threads :num => (size - 1),
                   :when_done => lambda { |num| @last_load_more_size = num }
    end
  end

  def lines; @text.length; end
  def [] i; @text[i]; end
  def contains_thread? t; !@lines[t].nil?; end

  def reload
    drop_all_threads
    BufferManager.draw_screen
    load_threads :num => buffer.content_height
  end

  ## open up a thread view window
  def select t=nil
    t ||= @threads[curpos] or return

    ## TODO: don't regen text completely
    Redwood::reporting_thread do
      BufferManager.say("Loading message bodies...") do |sid|
        t.each { |m, *o| m.load_from_source! if m }
      end
      mode = ThreadViewMode.new t, @hidden_labels
      BufferManager.spawn t.subj, mode
      BufferManager.draw_screen
      mode.jump_to_first_open
      BufferManager.draw_screen # lame TODO: make this unnecessary
      ## the first draw_screen is needed before topline and botline
      ## are set, and the second to show the cursor having moved

      t.remove_label :unread
      update_text_for_line curpos
      UpdateManager.relay self, :read, t
    end
  end

  def multi_select threads
    threads.each { |t| select t }
  end
  
  def handle_starred_update sender, m
    t = @ts.thread_for(m) or return
    l = @lines[t] or return
    update_text_for_line l
    BufferManager.draw_screen
  end

  def handle_read_update sender, t
    l = @lines[t] or return
    update_text_for_line @lines[t]
    BufferManager.draw_screen
  end

  def handle_archived_update *a; handle_read_update(*a); end

  ## overwrite me!
  def is_relevant? m; false; end

  def handle_add_update sender, m
    if is_relevant?(m) || @ts.is_relevant?(m)
      @ts.load_thread_for_message m
      update
      BufferManager.draw_screen
    end
  end

  def handle_delete_update sender, mid
    if @ts.contains_id? mid
      @ts.remove mid
      update
      BufferManager.draw_screen
    end
  end

  def update
    ## let's see you do THIS in python
    @threads = @ts.threads.select { |t| !@hidden_threads[t] }.sort_by { |t| t.date }.reverse
    @size_width = (@threads.map { |t| t.size }.max || 0).num_digits
    regen_text
  end

  def edit_message
    return unless(t = @threads[curpos])
    message, *crap = t.find { |m, *o| m.has_label? :draft }
    if message
      mode = ResumeMode.new message
      BufferManager.spawn "Edit message", mode
    else
      BufferManager.flash "Not a draft message!"
    end
  end

  def actually_toggle_starred t
    if t.has_label? :starred # if ANY message has a star
      t.remove_label :starred # remove from all
    else
      t.first.add_label :starred # add only to first
    end
  end  

  def toggle_starred 
    t = @threads[curpos] or return
    actually_toggle_starred t
    update_text_for_line curpos
    cursor_down
  end

  def multi_toggle_starred threads
    threads.each { |t| actually_toggle_starred t }
    regen_text
  end

  def actually_toggle_archived t
    if t.has_label? :inbox
      t.remove_label :inbox
      UpdateManager.relay self, :archived, t
    else
      t.apply_label :inbox
      UpdateManager.relay self, :unarchived, t
    end
  end

  def toggle_archived 
    t = @threads[curpos] or return
    actually_toggle_archived t
    update_text_for_line curpos
  end

  def multi_toggle_archived threads
    threads.each { |t| actually_toggle_archived t }
    regen_text
  end

  def toggle_new
    t = @threads[curpos] or return
    t.toggle_label :unread
    update_text_for_line curpos
    cursor_down
  end

  def multi_toggle_new threads
    threads.each { |t| t.toggle_label :unread }
    regen_text
  end

  def multi_toggle_tagged threads
    @tags.drop_all_tags
    regen_text
  end

  def jump_to_next_new
    n = ((curpos + 1) ... lines).find { |i| @threads[i].has_label? :unread }
    n = (0 ... curpos).find { |i| @threads[i].has_label? :unread } unless n
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
      t.toggle_label :spam
      hide_thread t
    end
    regen_text
  end

  def delete
    t = @threads[curpos] or return
    multi_delete [t]
  end

  def multi_delete threads
    threads.each do |t|
      t.toggle_label :deleted
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
    dirty_threads = (@threads + @hidden_threads.keys).select { |t| t.dirty? }
    return if dirty_threads.empty?

    BufferManager.say("Saving threads...") do |say_id|
      dirty_threads.each_with_index do |t, i|
        BufferManager.say "Saving modified thread #{i + 1} of #{dirty_threads.length}...", say_id
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
    thread = @threads[curpos] or return
    speciall = (@hidden_labels + LabelManager::RESERVED_LABELS).uniq
    keepl, modifyl = thread.labels.partition { |t| speciall.member? t }
    label_string = modifyl.join(" ")
    label_string += " " unless label_string.empty?

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
    m.load_from_source!
    mode = ReplyMode.new m
    BufferManager.spawn "Reply to #{m.subj}", mode
  end

  def forward
    t = @threads[curpos] or return
    m = t.latest_message
    return if m.nil? # probably won't happen
    m.load_from_source!
    mode = ForwardMode.new m
    BufferManager.spawn "Forward of #{m.subj}", mode
    mode.edit
  end

  def load_n_threads_background n=LOAD_MORE_THREAD_NUM, opts={}
    return if @load_thread # todo: wrap in mutex
    @load_thread = Redwood::reporting_thread do
      num = load_n_threads n, opts
      opts[:when_done].call(num) if opts[:when_done]
      @load_thread = nil
    end
  end

  def load_n_threads n=LOAD_MORE_THREAD_NUM, opts={}
    @mbid = BufferManager.say "Searching for threads..."
    orig_size = @ts.size
    last_update = Time.now - 9999 # oh yeah
    @ts.load_n_threads(@ts.size + n, opts) do |i|
      BufferManager.say "Loaded #{i} threads...", @mbid
      if (Time.now - last_update) >= 0.25
        update
        BufferManager.draw_screen
        last_update = Time.now
      end
    end
    @ts.threads.each { |th| th.labels.each { |l| LabelManager << l } }

    update
    BufferManager.clear @mbid
    @mbid = nil
    BufferManager.draw_screen
    @ts.size - orig_size
  end
  synchronized :load_n_threads

  def status
    if (l = lines) == 0
      "line 0 of 0"
    else
      "line #{curpos + 1} of #{l} #{dirty? ? '*modified*' : ''}"
    end
  end

  def load_threads opts={}
    n = opts[:num] || ThreadIndexMode::LOAD_MORE_THREAD_NUM

    myopts = @load_thread_opts.merge({ :when_done => (lambda do |num|
      opts[:when_done].call(num) if opts[:when_done]
      if num > 0
        BufferManager.flash "Found #{num} threads"
      else
        BufferManager.flash "No matches"
      end
    end)})

    if opts[:background] || opts[:background].nil?
      load_n_threads_background n, myopts
    else
      load_n_threads n, myopts
    end
  end

protected

  def cursor_thread; @threads[curpos]; end

  def drop_all_threads
    @tags.drop_all_tags
    initialize_threads
    update
  end

  def hide_thread t
    raise "already hidden" if @hidden_threads[t]
    @hidden_threads[t] = true
    @threads.delete t
    @tags.drop_tag_for t
  end

  def show_thread t
    if @hidden_threads[t]
      @hidden_threads.delete t
    else
      @ts.add_thread t
    end
    update
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
    t.authors.map do |p|
      if AccountManager.is_account?(p)
        "me"
      elsif t.authors.size == 1
        p.mediumname
      else
        p.shortname
      end
    end.uniq.join ","
  end

  def text_for_thread t
    date = t.date.to_nice_s
    from = author_text_for_thread t
    if from.length > @from_width
      from = from[0 ... (@from_width - 1)]
      from += "." unless from[-1] == ?\s
    end

    new = t.has_label?(:unread)
    starred = t.has_label?(:starred)

    dp = t.direct_participants.any? { |p| AccountManager.is_account? p }
    p = dp || t.participants.any? { |p| AccountManager.is_account? p }

    base_color =
      if new
        :index_new_color
      elsif starred
        :index_starred_color
      else 
        :index_old_color
      end

    [ 
      [:tagged_color, @tags.tagged?(t) ? ">" : " "],
      [:none, sprintf("%#{@date_width}s", date)],
      (starred ? [:starred_color, "*"] : [:none, " "]),
      [base_color, sprintf("%-#{@from_width}s", from)],
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
    @ts = ThreadSet.new Index.instance, $config[:thread_by_subject]
    @ts_mutex = Mutex.new
    @hidden_threads = {}
  end
end

end
