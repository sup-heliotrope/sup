module Redwood

## subclasses should implement:
## - is_relevant?

class ThreadIndexMode < LineCursorMode
  include CanSpawnForwardMode

  DATE_WIDTH = Time::TO_NICE_S_MAX_LEN
  MIN_FROM_WIDTH = 15
  LOAD_MORE_THREAD_NUM = 20

  HookManager.register "index-mode-size-widget", <<EOS
Generates the per-thread size widget for each thread.
Variables:
  thread: The message thread to be formatted.
EOS

  register_keymap do |k|
    k.add :load_threads, "Load #{LOAD_MORE_THREAD_NUM} more threads", 'M'
    k.add :reload, "Refresh view", '@'
    k.add :toggle_archived, "Toggle archived status", 'a'
    k.add :toggle_starred, "Star or unstar all messages in thread", '*'
    k.add :toggle_new, "Toggle new/read status of all messages in thread", 'N'
    k.add :edit_labels, "Edit or add labels for a thread", 'l'
    k.add :edit_message, "Edit message (drafts only)", 'e'
    k.add :toggle_spam, "Mark/unmark thread as spam", 'S'
    k.add :toggle_deleted, "Delete/undelete thread", 'd'
    k.add :kill, "Kill thread (never to be seen in inbox again)", '&'
    k.add :save, "Save changes now", '$'
    k.add :jump_to_next_new, "Jump to next new thread", :tab
    k.add :reply, "Reply to latest message in a thread", 'r'
    k.add :forward, "Forward latest message in a thread", 'f'
    k.add :toggle_tagged, "Tag/untag selected thread", 't'
    k.add :toggle_tagged_all, "Tag/untag all threads", 'T'
    k.add :apply_to_tagged, "Apply next command to all tagged threads", ';'
  end

  def initialize hidden_labels=[], load_thread_opts={}
    super()
    @mutex = Mutex.new # covers the following variables:
    @threads = {}
    @hidden_threads = {}
    @size_widget_width = nil
    @size_widgets = {}
    @tags = Tagger.new self

    ## these guys, and @text and @lines, are not covered
    @load_thread = nil
    @load_thread_opts = load_thread_opts
    @hidden_labels = hidden_labels + LabelManager::HIDDEN_RESERVED_LABELS
    @date_width = DATE_WIDTH
    
    initialize_threads # defines @ts and @ts_mutex
    update # defines @text and @lines

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
  #def contains_thread? t; !@lines[t].nil?; end
  def contains_thread? t; @threads.contains?(t) end

  def reload
    drop_all_threads
    BufferManager.draw_screen
    load_threads :num => buffer.content_height
  end

  ## open up a thread view window
  def select t=nil
    t ||= cursor_thread or return

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

      update_text_for_line curpos
      UpdateManager.relay self, :read, t
    end
  end

  def multi_select threads
    threads.each { |t| select t }
  end
  
  def handle_label_update sender, m
    t = @ts_mutex.synchronize { @ts.thread_for(m) } or return
    handle_label_thread_update sender, t
  end

  def handle_label_thread_update sender, t
    l = @lines[t] or return
    update_text_for_line l
    BufferManager.draw_screen
  end

  def handle_read_update sender, t
    l = @lines[t] or return
    update_text_for_line l
    BufferManager.draw_screen
  end

  def handle_archived_update *a; handle_read_update(*a); end

  def handle_deleted_update sender, t
    handle_read_update sender, t
    hide_thread t
    regen_text
  end

  ## overwrite me!
  def is_relevant? m; false; end

  def handle_add_update sender, m
    @ts_mutex.synchronize do
      return unless is_relevant?(m) || @ts.is_relevant?(m)
      @ts.load_thread_for_message m
    end
    update
    BufferManager.draw_screen
  end

  def handle_delete_update sender, mid
    @ts_mutex.synchronize do
      return unless @ts.contains_id? mid
      @ts.remove mid
    end
    update
    BufferManager.draw_screen
  end

  def update
    @mutex.synchronize do
      ## let's see you do THIS in python
      @threads = @ts.threads.select { |t| !@hidden_threads[t] }.sort_by { |t| t.date }.reverse
      @size_widgets = @threads.map { |t| size_widget_for_thread t }
      @size_widget_width = @size_widgets.max_of { |w| w.length }
    end

    regen_text
  end

  def edit_message
    return unless(t = cursor_thread)
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
      UpdateManager.relay self, :unstarred, t
    else
      t.first.add_label :starred # add only to first
      UpdateManager.relay self, :starred, t
    end
  end  

  def toggle_starred 
    t = cursor_thread or return
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

  def actually_toggle_spammed t
    if t.has_label? :spam
      t.remove_label :spam
      UpdateManager.relay self, :unspammed, t
    else
      t.apply_label :spam
      UpdateManager.relay self, :spammed, t
    end
  end

  def actually_toggle_deleted t
    if t.has_label? :deleted
      t.remove_label :deleted
      UpdateManager.relay self, :undeleted, t
    else
      t.apply_label :deleted
      UpdateManager.relay self, :deleted, t
    end
  end

  def toggle_archived 
    t = cursor_thread or return
    actually_toggle_archived t
    update_text_for_line curpos
  end

  def multi_toggle_archived threads
    threads.each { |t| actually_toggle_archived t }
    regen_text
  end

  def toggle_new
    t = cursor_thread or return
    t.toggle_label :unread
    update_text_for_line curpos
    cursor_down
  end

  def multi_toggle_new threads
    threads.each { |t| t.toggle_label :unread }
    regen_text
  end

  def multi_toggle_tagged threads
    @mutex.synchronize { @tags.drop_all_tags }
    regen_text
  end

  def jump_to_next_new
    n = @mutex.synchronize do
      ((curpos + 1) ... lines).find { |i| @threads[i].has_label? :unread } ||
        (0 ... curpos).find { |i| @threads[i].has_label? :unread }
    end
    if n
      ## jump there if necessary
      jump_to_line n unless n >= topline && n < botline
      set_cursor_pos n
    else
      BufferManager.flash "No new messages"
    end
  end

  def toggle_spam
    t = cursor_thread or return
    multi_toggle_spam [t]
  end

  ## both spam and deleted have the curious characteristic that you
  ## always want to hide the thread after either applying or removing
  ## that label. in all thread-index-views except for
  ## label-search-results-mode, when you mark a message as spam or
  ## deleted, you want it to disappear immediately; in LSRM, you only
  ## see deleted or spam emails, and when you undelete or unspam them
  ## you also want them to disappear immediately.
  def multi_toggle_spam threads
    threads.each do |t|
      actually_toggle_spammed t
      hide_thread t 
    end
    regen_text
  end

  def toggle_deleted
    t = cursor_thread or return
    multi_toggle_deleted [t]
  end

  ## see comment for multi_toggle_spam
  def multi_toggle_deleted threads
    threads.each do |t|
      actually_toggle_deleted t
      hide_thread t 
    end
    regen_text
  end

  def kill
    t = cursor_thread or return
    multi_kill [t]
  end

  def multi_kill threads
    threads.each do |t|
      t.apply_label :killed
      hide_thread t
    end
    regen_text
    BufferManager.flash "#{threads.size.pluralize 'Thread'} killed."
  end

  def save
    dirty_threads = @mutex.synchronize { (@threads + @hidden_threads.keys).select { |t| t.dirty? } }
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
    t = cursor_thread or return
    @mutex.synchronize { @tags.toggle_tag_for t }
    update_text_for_line curpos
    cursor_down
  end
  
  def toggle_tagged_all
    @mutex.synchronize { @threads.each { |t| @tags.toggle_tag_for t } }
    regen_text
  end

  def apply_to_tagged; @tags.apply_to_tagged; end

  def edit_labels
    thread = cursor_thread or return
    speciall = (@hidden_labels + LabelManager::RESERVED_LABELS).uniq
    keepl, modifyl = thread.labels.partition { |t| speciall.member? t }

    user_labels = BufferManager.ask_for_labels :label, "Labels for thread: ", modifyl, @hidden_labels

    return unless user_labels
    thread.labels = keepl + user_labels
    user_labels.each { |l| LabelManager << l }
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
    t = cursor_thread or return
    m = t.latest_message
    return if m.nil? # probably won't happen
    m.load_from_source!
    mode = ReplyMode.new m
    BufferManager.spawn "Reply to #{m.subj}", mode
  end

  def forward
    t = cursor_thread or return
    m = t.latest_message
    return if m.nil? # probably won't happen
    m.load_from_source!
    spawn_forward_mode m
  end

  def load_n_threads_background n=LOAD_MORE_THREAD_NUM, opts={}
    return if @load_thread # todo: wrap in mutex
    @load_thread = Redwood::reporting_thread do
      num = load_n_threads n, opts
      opts[:when_done].call(num) if opts[:when_done]
      @load_thread = nil
    end
  end

  ## TODO: figure out @ts_mutex in this method
  def load_n_threads n=LOAD_MORE_THREAD_NUM, opts={}
    @mbid = BufferManager.say "Searching for threads..."
    orig_size = @ts.size
    last_update = Time.now
    @ts.load_n_threads(@ts.size + n, opts) do |i|
      if (Time.now - last_update) >= 0.25
        BufferManager.say "Loaded #{i.pluralize 'thread'}...", @mbid
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
  ignore_concurrent_calls :load_n_threads

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
        BufferManager.flash "Found #{num.pluralize 'thread'}."
      else
        BufferManager.flash "No matches."
      end
    end)})

    if opts[:background] || opts[:background].nil?
      load_n_threads_background n, myopts
    else
      load_n_threads n, myopts
    end
  end
  ignore_concurrent_calls :load_threads

  def resize rows, cols
    regen_text
    super
  end

protected

  def size_widget_for_thread t
    HookManager.run("index-mode-size-widget", :thread => t) || default_size_widget_for(t)
  end

  def cursor_thread; @mutex.synchronize { @threads[curpos] }; end

  def drop_all_threads
    @tags.drop_all_tags
    initialize_threads
    update
  end

  def hide_thread t
    @mutex.synchronize do
      raise "already hidden" if @hidden_threads[t]
      @hidden_threads[t] = true
      i = @threads.index t
      @threads.delete_at i
      @size_widgets.delete_at i
      @tags.drop_tag_for t
    end
  end

  def update_text_for_line l
    return unless l # not sure why this happens, but it does, occasionally
    
    need_update = false

    @mutex.synchronize do
      @size_widgets[l] = size_widget_for_thread @threads[l]

      ## if the widget size has increased, we need to redraw everyone
      need_update = @size_widgets[l].size > @size_widget_width
    end

    if need_update
      update
    else
      @text[l] = text_for_thread_at l
      buffer.mark_dirty if buffer
    end
  end

  def regen_text
    threads = @mutex.synchronize { @threads }
    @text = threads.map_with_index { |t, i| text_for_thread_at i }
    @lines = threads.map_with_index { |t, i| [t, i] }.to_h
    buffer.mark_dirty if buffer
  end
  
  def authors; map { |m, *o| m.from if m }.compact.uniq; end

  def author_names_and_newness_for_thread t
    new = {}
    authors = t.map do |m, *o|
      next unless m

      name = 
        if AccountManager.is_account?(m.from)
          "me"
        elsif t.authors.size == 1
          m.from.mediumname
        else
          m.from.shortname
        end

      new[name] ||= m.has_label?(:unread)
      name
    end

    authors.compact.uniq.map { |a| [a, new[a]] }
  end

  def text_for_thread_at line
    t, size_widget = @mutex.synchronize { [@threads[line], @size_widgets[line]] }

    date = t.date.to_nice_s

    new = t.has_label?(:unread)
    starred = t.has_label?(:starred)

    ## format the from column
    cur_width = 0
    ann = author_names_and_newness_for_thread t
    from = []
    ann.each_with_index do |(name, newness), i|
      break if cur_width >= from_width
      last = i == ann.length - 1

      abbrev =
        if cur_width + name.length > from_width
          name[0 ... (from_width - cur_width - 1)] + "."
        elsif cur_width + name.length == from_width
          name[0 ... (from_width - cur_width)]
        else
          if last
            name[0 ... (from_width - cur_width)]
          else
            name[0 ... (from_width - cur_width - 1)] + "," 
          end
        end

      cur_width += abbrev.length

      if last && from_width > cur_width
        abbrev += " " * (from_width - cur_width)
      end

      from << [(newness ? :index_new_color : (starred ? :index_starred_color : :index_old_color)), abbrev]
    end

    dp = t.direct_participants.any? { |p| AccountManager.is_account? p }
    p = dp || t.participants.any? { |p| AccountManager.is_account? p }

    subj_color =
      if new
        :index_new_color
      elsif starred
        :index_starred_color
      else 
        :index_old_color
      end

    snippet = t.snippet + (t.snippet.empty? ? "" : "...")

    size_widget_text = sprintf "%#{ @size_widget_width}s", size_widget

    [ 
      [:tagged_color, @tags.tagged?(t) ? ">" : " "],
      [:none, sprintf("%#{@date_width}s", date)],
      (starred ? [:starred_color, "*"] : [:none, " "]),
    ] +
      from +
      [
      [subj_color, size_widget_text],
      [:to_me_color, dp ? " >" : (p ? ' +' : "  ")],
      [subj_color, t.subj + (t.subj.empty? ? "" : " ")],
    ] +
      (t.labels - @hidden_labels).map { |label| [:label_color, "+#{label} "] } +
      [[:snippet_color, snippet]
    ]

  end

  def dirty?; @mutex.synchronize { (@hidden_threads.keys + @threads).any? { |t| t.dirty? } } end

private

  def default_size_widget_for t
    case t.size
    when 1
      ""
    else
      "(#{t.size})"
    end
  end

  def from_width
    [(buffer.content_width.to_f * 0.2).to_i, MIN_FROM_WIDTH].max
  end

  def initialize_threads
    @ts = ThreadSet.new Index.instance, $config[:thread_by_subject]
    @ts_mutex = Mutex.new
    @hidden_threads = {}
  end
end

end
