module Redwood

class ThreadViewMode < LineCursorMode
  include M17n

  ## this holds all info we need to lay out a message
  class MessageLayout
    attr_accessor :top, :bot, :prev, :next, :depth, :width, :state, :color, :star_color, :orig_new
  end

  class ChunkLayout
    attr_accessor :state
  end

  DATE_FORMAT = "%B %e %Y %l:%M%P"
  INDENT_SPACES = 2 # how many spaces to indent child messages

  HookManager.register "detailed-headers", <<EOS
Add or remove headers from the detailed header display of a message.
Variables:
  message: The message whose headers are to be formatted.
  headers: A hash of header (name, value) pairs, initialized to the default
           headers.
Return value:
  None. The variable 'headers' should be modified in place.
EOS

  HookManager.register "bounce-command", <<EOS
Determines the command used to bounce a message.
Variables:
      from: The From header of the message being bounced
            (eg: likely _not_ your address).
        to: The addresses you asked the message to be bounced to as an array.
Return value:
  A string representing the command to pipe the mail into.  This
  should include the entire command except for the destination addresses,
  which will be appended by sup.
EOS

  register_keymap do |k|
    km = m('thread_view.keymap')
    k.add :toggle_detailed_header, km['toggle_detailed_header'], 'h'
    k.add :show_header, km['show_header'], 'H'
    k.add :show_message, km['show_message'], 'V'
    k.add :activate_chunk, km['activate_chunk'], :enter
    k.add :expand_all_messages, km['expand_all_messages'], 'E'
    k.add :edit_draft, km['edit_draft'], 'e'
    k.add :send_draft, km['send_draft'], 'y'
    k.add :edit_labels, km['edit_labels'], 'l'
    k.add :expand_all_quotes, km['expand_all_quotes'], 'o'
    k.add :jump_to_next_open, km['jump_to_next_open'], 'n'
    k.add :jump_to_prev_open, km['jump_to_prev_open'], 'p'
    k.add :align_current_message, km['align_current_message'], 'z'
    k.add :toggle_starred, km['toggle_starred'], '*'
    k.add :toggle_new, km['toggle_new'], 'N'
#    k.add :collapse_non_new_messages, "Collapse all but unread messages", 'N'
    k.add :reply, km['reply'], 'r'
    k.add :reply_all, km['reply_all'], 'G'
    k.add :forward, km['forward'], 'f'
    k.add :bounce, km['bounce'], '!'
    k.add :alias, km['alias'], 'i'
    k.add :edit_as_new, km['edit_as_new'], 'D'
    k.add :save_to_disk, km['save_to_disk'], 's'
    k.add :save_all_to_disk, km['save_all_to_disk'], 'A'
    k.add :search, km['search'], 'S'
    k.add :compose, km['compose'], 'm'
    k.add :subscribe_to_list, km['subscribe_to_list'], "("
    k.add :unsubscribe_from_list, km['unsubscribe_from_list'], ")"
    k.add :pipe_message, km['pipe_message'], '|'

    k.add :archive_and_next, km['archive_and_next'], 'a'
    k.add :delete_and_next, km['delete_and_next'], 'd'

    k.add_multi km['add_multi_01'], '.' do |kk|
      kk.add :archive_and_kill, km['archive_and_kill'], 'a'
      kk.add :delete_and_kill, km['delete_and_kill'], 'd'
      kk.add :spam_and_kill, km['spam_and_kill'], 's'
      kk.add :unread_and_kill, km['unread_and_kill'], 'N'
    end

    k.add_multi km['add_multi_02'], ',' do |kk|
      kk.add :archive_and_next, km['archive_and_next'], 'a'
      kk.add :delete_and_next, km['delete_and_next'], 'd'
      kk.add :spam_and_next, km['spam_and_next'], 's'
      kk.add :unread_and_next, km['unread_and_next'], 'N'
      kk.add :do_nothing_and_next, km['do_nothing_and_next'], 'n'
    end

    k.add_multi km['add_multi_02'], ']' do |kk|
      kk.add :archive_and_prev, km['archive_and_prev'], 'a'
      kk.add :delete_and_prev, km['delete_and_prev'], 'd'
      kk.add :spam_and_prev, km['spam_and_prev'], 's'
      kk.add :unread_and_prev, km['unread_and_prev'], 'N'
      kk.add :do_nothing_and_prev, km['do_nothing_and_prev'], 'n'
    end
  end

  ## there are a couple important instance variables we hold to format
  ## the thread and to provide line-based functionality. @layout is a
  ## map from Messages to MessageLayouts, and @chunk_layout from
  ## Chunks to ChunkLayouts.  @message_lines is a map from row #s to
  ## Message objects.  @chunk_lines is a map from row #s to Chunk
  ## objects. @person_lines is a map from row #s to Person objects.

  def initialize thread, hidden_labels=[], index_mode=nil
    super()
    @thread = thread
    @hidden_labels = hidden_labels

    ## used for dispatch-and-next
    @index_mode = index_mode
    @dying = false

    @layout = SavingHash.new { MessageLayout.new }
    @chunk_layout = SavingHash.new { ChunkLayout.new }
    earliest, latest = nil, nil
    latest_date = nil
    altcolor = false

    @thread.each do |m, d, p|
      next unless m
      earliest ||= m
      @layout[m].state = initial_state_for m
      @layout[m].color = altcolor ? :alternate_patina_color : :message_patina_color
      @layout[m].star_color = altcolor ? :alternate_starred_patina_color : :starred_patina_color
      @layout[m].orig_new = m.has_label? :read
      altcolor = !altcolor
      if latest_date.nil? || m.date > latest_date
        latest_date = m.date
        latest = m
      end
    end

    @layout[latest].state = :open if @layout[latest].state == :closed
    @layout[earliest].state = :detailed if earliest.has_label?(:unread) || @thread.size == 1

    @thread.remove_label :unread
    regen_text
  end

  def draw_line ln, opts={}
    if ln == curpos
      super ln, :highlight => true
    else
      super
    end
  end
  def lines; @text.length; end
  def [] i; @text[i]; end

  def show_header
    m = @message_lines[curpos] or return
    BufferManager.spawn_unless_exists(m('thread_view.full_header_for', :id => m.id)) do
      TextMode.new m.raw_header
    end
  end

  def show_message
    m = @message_lines[curpos] or return
    BufferManager.spawn_unless_exists(m('thread_view.raw_message_for', :id => m.id)) do
      TextMode.new m.raw_message
    end
  end

  def toggle_detailed_header
    m = @message_lines[curpos] or return
    @layout[m].state = (@layout[m].state == :detailed ? :open : :detailed)
    update
  end

  def reply type_arg=nil
    m = @message_lines[curpos] or return
    mode = ReplyMode.new m, type_arg
    BufferManager.spawn m('thread_view.reply_to', :subject => m.subj), mode
  end

  def reply_all; reply :all; end

  def subscribe_to_list
    m = @message_lines[curpos] or return
    if m.list_subscribe && m.list_subscribe =~ /<mailto:(.*?)(\?subject=(.*?))?>/
      ComposeMode.spawn_nicely :from => AccountManager.account_for(m.recipient_email), :to => [Person.from_address($1)], :subj => ($3 || "subscribe")
    else
      BufferManager.flash m('flash.info.cant_find_list_subscribe_header')
    end
  end

  def unsubscribe_from_list
    m = @message_lines[curpos] or return
    if m.list_unsubscribe && m.list_unsubscribe =~ /<mailto:(.*?)(\?subject=(.*?))?>/
      ComposeMode.spawn_nicely :from => AccountManager.account_for(m.recipient_email), :to => [Person.from_address($1)], :subj => ($3 || "unsubscribe")
    else
      BufferManager.flash m('thread_view.cant_find_list_unsubscribe_header')
    end
  end

  def forward
    if(chunk = @chunk_lines[curpos]) && chunk.is_a?(Chunk::Attachment)
      ForwardMode.spawn_nicely :attachments => [chunk]
    elsif(m = @message_lines[curpos])
      ForwardMode.spawn_nicely :message => m
    end
  end

  def bounce
    m = @message_lines[curpos] or return
    to = BufferManager.ask_for_contacts(:people, "Bounce To: ") or return

    defcmd = AccountManager.default_account.sendmail.sub(/\s(\-(ti|it|t))\b/) do |match|
      case "$1"
        when '-t' then ''
        else ' -i'
      end
    end

    cmd = case (hookcmd = HookManager.run "bounce-command", :from => m.from, :to => to)
          when nil, /^$/ then defcmd
          else hookcmd
          end + ' ' + to.map { |t| t.email }.join(' ')

    bt = to.size > 1 ? "#{to.size} recipients" : to.to_s

    if BufferManager.ask_yes_or_no "Really bounce to #{bt}?"
      debug "bounce command: #{cmd}"
      begin
        IO.popen(cmd, 'w') do |sm|
          sm.puts m.raw_message
        end
        raise SendmailCommandFailed, "Couldn't execute #{cmd}" unless $? == 0
      rescue SystemCallError, SendmailCommandFailed => e
        warn "problem sending mail: #{e.message}"
        BufferManager.flash m('flash.warn.problem_sending_mail', :message => e.message)
      end
    end
  end

  include CanAliasContacts
  def alias
    p = @person_lines[curpos] or return
    alias_contact p
    update
  end

  def search
    p = @person_lines[curpos] or return
    mode = PersonSearchResultsMode.new [p]
    BufferManager.spawn m('thread_view.search_for', :name => p.name), mode
    mode.load_threads :num => mode.buffer.content_height
  end

  def compose
    p = @person_lines[curpos]
    if p
      ComposeMode.spawn_nicely :to_default => p
    else
      ComposeMode.spawn_nicely
    end
  end

  def edit_labels
    reserved_labels = @thread.labels.select { |l| LabelManager::RESERVED_LABELS.include? l }
    new_labels = BufferManager.ask_for_labels :label, "#{m('thread_view.ask.labels_for_thread')}: ", @thread.labels

    return unless new_labels
    @thread.labels = Set.new(reserved_labels) + new_labels
    new_labels.each { |l| LabelManager << l }
    update
    UpdateManager.relay self, :labeled, @thread.first
  end

  def toggle_starred
    m = @message_lines[curpos] or return
    toggle_label m, :starred
  end

  def toggle_new
    m = @message_lines[curpos] or return
    toggle_label m, :unread
  end

  def toggle_label m, label
    if m.has_label? label
      m.remove_label label
    else
      m.add_label label
    end
    ## TODO: don't recalculate EVERYTHING just to add a stupid little
    ## star to the display
    update
    UpdateManager.relay self, :single_message_labeled, m
  end

  ## called when someone presses enter when the cursor is highlighting
  ## a chunk. for expandable chunks (including messages) we toggle
  ## open/closed state; for viewable chunks (like attachments) we
  ## view.
  def activate_chunk
    chunk = @chunk_lines[curpos] or return
    if chunk.is_a? Chunk::Text
      ## if the cursor is over a text region, expand/collapse the
      ## entire message
      chunk = @message_lines[curpos]
    end
    layout = if chunk.is_a?(Message)
      @layout[chunk]
    elsif chunk.expandable?
      @chunk_layout[chunk]
    end
    if layout
      layout.state = (layout.state != :closed ? :closed : :open)
      #cursor_down if layout.state == :closed # too annoying
      update
    elsif chunk.viewable?
      view chunk
    end
    if chunk.is_a?(Message)
      jump_to_message chunk
      jump_to_next_open if layout.state == :closed
    end
  end

  def edit_as_new
    m = @message_lines[curpos] or return
    mode = ComposeMode.new(:body => m.quotable_body_lines, :to => m.to, :cc => m.cc, :subj => m.subj, :bcc => m.bcc, :refs => m.refs, :replytos => m.replytos)
    BufferManager.spawn "edit as new", mode
    mode.edit_message
  end

  def save_to_disk
    chunk = @chunk_lines[curpos] or return
    case chunk
    when Chunk::Attachment
      default_dir = File.join(($config[:default_attachment_save_dir] || "."), chunk.filename)
      fn = BufferManager.ask_for_filename :filename, "#{m('thread_view.ask.save_attachment_to_file')}: ", default_dir
      save_to_file(fn) { |f| f.print chunk.raw_content } if fn
    else
      m = @message_lines[curpos]
      fn = BufferManager.ask_for_filename :filename, "#{m('thread_view.ask.save_message_to_file')}: "
      return unless fn
      save_to_file(fn) do |f|
        m.each_raw_message_line { |l| f.print l }
      end
    end
  end

  def save_all_to_disk
    m = @message_lines[curpos] or return
    default_dir = ($config[:default_attachment_save_dir] || ".")
    folder = BufferManager.ask_for_filename :filename, "#{m('thread_view.ask.save_all_attachments_to_folder')}: ", default_dir, true
    return unless folder

    num = 0
    num_errors = 0
    m.chunks.each do |chunk|
      next unless chunk.is_a?(Chunk::Attachment)
      fn = File.join(folder, chunk.filename)
      num_errors += 1 unless save_to_file(fn, false) { |f| f.print chunk.raw_content }
      num += 1
    end

    if num == 0
      BufferManager.flash m('flash.warn.didnt_find_any_attachments')
    else
      if num_errors == 0
        msg = num > 1 ? 'wrote_n_attachments_to_folder' : 'wrote_one_attachment_to_folder'
        BufferManager.flash m("flash.info.#{msg}", :n => num, :folder => folder)
      else
        msg = (num - num_errors) > 1 ? 'wrote_n_attachments_to_folder' : 'wrote_one_attachment_to_folder'
        notice = m("flash.info.#{msg}", :n => (num - num_errors), :folder => folder)
        notice += "; "
        notice += m('flash.info.couldnt_write_n_attachments', :n => num_errors)
        BufferManager.flash notice
      end
    end
  end

  def edit_draft
    m = @message_lines[curpos] or return
    if m.is_draft?
      mode = ResumeMode.new m
      BufferManager.spawn m('thread_index.edit_message'), mode
      BufferManager.kill_buffer self.buffer
      mode.edit_message
    else
      BufferManager.flash m('flash.info.not_a_draft_message')
    end
  end

  def send_draft
    m = @message_lines[curpos] or return
    if m.is_draft?
      mode = ResumeMode.new m
      BufferManager.spawn m('message.editing.keymap.send_message'), mode
      BufferManager.kill_buffer self.buffer
      mode.send_message
    else
      BufferManager.flash m('flash.info.not_a_draft_message')
    end
  end

  def jump_to_first_open
    m = @message_lines[0] or return
    if @layout[m].state != :closed
      jump_to_message m#, true
    else
      jump_to_next_open #true
    end
  end

  def jump_to_next_open force_alignment=nil
    return continue_search_in_buffer if in_search? # hack: allow 'n' to apply to both operations
    m = (curpos ... @message_lines.length).argfind { |i| @message_lines[i] }
    return unless m
    while nextm = @layout[m].next
      break if @layout[nextm].state != :closed
      m = nextm
    end
    jump_to_message nextm, force_alignment if nextm
  end

  def align_current_message
    m = @message_lines[curpos] or return
    jump_to_message m, true
  end

  def jump_to_prev_open
    m = (0 .. curpos).to_a.reverse.argfind { |i| @message_lines[i] } # bah, .to_a
    return unless m
    ## jump to the top of the current message if we're in the body;
    ## otherwise, to the previous message

    top = @layout[m].top
    if curpos == top
      while(prevm = @layout[m].prev)
        break if @layout[prevm].state != :closed
        m = prevm
      end
      jump_to_message prevm if prevm
    else
      jump_to_message m
    end
  end

  def jump_to_message m, force_alignment=false
    l = @layout[m]

    ## boundaries of the message
    message_left = l.depth * INDENT_SPACES
    message_right = message_left + l.width

    ## calculate leftmost colum
    left = if force_alignment # force mode: align exactly
      message_left
    else # regular: minimize cursor movement
      ## leftmost and rightmost are boundaries of all valid left-column
      ## alignments.
      leftmost = [message_left, message_right - buffer.content_width + 1].min
      rightmost = message_left
      leftcol.clamp(leftmost, rightmost)
    end

    jump_to_line l.top    # move vertically
    jump_to_col left      # move horizontally
    set_cursor_pos l.top  # set cursor pos
  end

  def expand_all_messages
    @global_message_state ||= :closed
    @global_message_state = (@global_message_state == :closed ? :open : :closed)
    @layout.each { |m, l| l.state = @global_message_state }
    update
  end

  def collapse_non_new_messages
    @layout.each { |m, l| l.state = l.orig_new ? :open : :closed }
    update
  end

  def expand_all_quotes
    if(m = @message_lines[curpos])
      quotes = m.chunks.select { |c| (c.is_a?(Chunk::Quote) || c.is_a?(Chunk::Signature)) && c.lines.length > 1 }
      numopen = quotes.inject(0) { |s, c| s + (@chunk_layout[c].state == :open ? 1 : 0) }
      newstate = numopen > quotes.length / 2 ? :closed : :open
      quotes.each { |c| @chunk_layout[c].state = newstate }
      update
    end
  end

  def cleanup
    @layout = @chunk_layout = @text = nil # for good luck
  end

  def archive_and_kill; archive_and_then :kill end
  def spam_and_kill; spam_and_then :kill end
  def delete_and_kill; delete_and_then :kill end
  def unread_and_kill; unread_and_then :kill end

  def archive_and_next; archive_and_then :next end
  def spam_and_next; spam_and_then :next end
  def delete_and_next; delete_and_then :next end
  def unread_and_next; unread_and_then :next end
  def do_nothing_and_next; do_nothing_and_then :next end

  def archive_and_prev; archive_and_then :prev end
  def spam_and_prev; spam_and_then :prev end
  def delete_and_prev; delete_and_then :prev end
  def unread_and_prev; unread_and_then :prev end
  def do_nothing_and_prev; do_nothing_and_then :prev end

  def archive_and_then op
    dispatch op do
      @thread.remove_label :inbox
      UpdateManager.relay self, :archived, @thread.first
    end
  end

  def spam_and_then op
    dispatch op do
      @thread.apply_label :spam
      UpdateManager.relay self, :spammed, @thread.first
    end
  end

  def delete_and_then op
    dispatch op do
      @thread.apply_label :deleted
      UpdateManager.relay self, :deleted, @thread.first
    end
  end

  def unread_and_then op
    dispatch op do
      @thread.apply_label :unread
      UpdateManager.relay self, :unread, @thread.first
    end
  end

  def do_nothing_and_then op
    dispatch op
  end

  def dispatch op
    return if @dying
    @dying = true

    l = lambda do
      yield if block_given?
      BufferManager.kill_buffer_safely buffer
    end

    case op
    when :next
      @index_mode.launch_next_thread_after @thread, &l
    when :prev
      @index_mode.launch_prev_thread_before @thread, &l
    when :kill
      l.call
    else
      raise ArgumentError, "unknown thread dispatch operation #{op.inspect}"
    end
  end
  private :dispatch

  def pipe_message
    chunk = @chunk_lines[curpos]
    chunk = nil unless chunk.is_a?(Chunk::Attachment)
    message = @message_lines[curpos] unless chunk

    return unless chunk || message

    command = BufferManager.ask(:shell, "#{m('text.ask.pipe_command')}: ")
    return if command.nil? || command.empty?

    output = pipe_to_process(command) do |stream|
      if chunk
        stream.print chunk.raw_content
      else
        message.each_raw_message_line { |l| stream.print l }
      end
    end

    if output
      BufferManager.spawn "#{m('text.output_of')} '#{command}'", TextMode.new(output)
    else
      BufferManager.flash "'#{command}' #{m('words.done')}!"
    end
  end

private

  def initial_state_for m
    if m.has_label?(:starred) || m.has_label?(:unread)
      :open
    else
      :closed
    end
  end

  def update
    regen_text
    buffer.mark_dirty if buffer
  end

  ## here we generate the actual content lines. we accumulate
  ## everything into @text, and we set @chunk_lines and
  ## @message_lines, and we update @layout.
  def regen_text
    @text = []
    @chunk_lines = []
    @message_lines = []
    @person_lines = []

    prevm = nil
    @thread.each do |m, depth, parent|
      unless m.is_a? Message # handle nil and :fake_root
        @text += chunk_to_lines m, nil, @text.length, depth, parent
        next
      end
      l = @layout[m]

      ## is this still necessary?
      next unless @layout[m].state # skip discarded drafts

      ## build the patina
      text = chunk_to_lines m, l.state, @text.length, depth, parent, l.color, l.star_color

      l.top = @text.length
      l.bot = @text.length + text.length # updated below
      l.prev = prevm
      l.next = nil
      l.depth = depth
      # l.state we preserve
      l.width = 0 # updated below
      @layout[l.prev].next = m if l.prev

      (0 ... text.length).each do |i|
        @chunk_lines[@text.length + i] = m
        @message_lines[@text.length + i] = m
        lw = text[i].flatten.select { |x| x.is_a? String }.map { |x| x.display_length }.sum
      end

      @text += text
      prevm = m
      if l.state != :closed
        m.chunks.each do |c|
          cl = @chunk_layout[c]

          ## set the default state for chunks
          cl.state ||=
            if c.expandable? && c.respond_to?(:initial_state)
              c.initial_state
            else
              :closed
            end

          text = chunk_to_lines c, cl.state, @text.length, depth
          (0 ... text.length).each do |i|
            @chunk_lines[@text.length + i] = c
            @message_lines[@text.length + i] = m
            lw = text[i].flatten.select { |x| x.is_a? String }.map { |x| x.display_length }.sum - (depth * INDENT_SPACES)
            l.width = lw if lw > l.width
          end
          @text += text
        end
        @layout[m].bot = @text.length
      end
    end
  end

  def message_patina_lines m, state, start, parent, prefix, color, star_color
    prefix_widget = [color, prefix]

    open_widget = [color, (state == :closed ? "+ " : "- ")]
    new_widget = [color, (m.has_label?(:unread) ? "N" : " ")]
    starred_widget = if m.has_label?(:starred)
        [star_color, "*"]
      else
        [color, " "]
      end
    attach_widget = [color, (m.has_label?(:attachment) ? "@" : " ")]

    case state
    when :open
      @person_lines[start] = m.from
      [[prefix_widget, open_widget, new_widget, attach_widget, starred_widget,
        [color,
            "#{m.from ? m.from.mediumname : '?'} to #{m.recipients.map { |l| l.shortname }.join(', ')} #{m.date.to_nice_s} (#{m.date.to_nice_distance_s})"]]]

    when :closed
      @person_lines[start] = m.from
      [[prefix_widget, open_widget, new_widget, attach_widget, starred_widget,
        [color,
        "#{m.from ? m.from.mediumname : '?'}, #{m.date.to_nice_s} (#{m.date.to_nice_distance_s})  #{m.snippet}"]]]

    when :detailed
      @person_lines[start] = m.from
      from_line = [[prefix_widget, open_widget, new_widget, attach_widget, starred_widget,
          [color, "From: #{m.from ? format_person(m.from) : '?'}"]]]

      addressee_lines = []
      unless m.to.empty?
        m.to.each_with_index { |p, i| @person_lines[start + addressee_lines.length + from_line.length + i] = p }
        addressee_lines += format_person_list "   To: ", m.to
      end
      unless m.cc.empty?
        m.cc.each_with_index { |p, i| @person_lines[start + addressee_lines.length + from_line.length + i] = p }
        addressee_lines += format_person_list "   Cc: ", m.cc
      end
      unless m.bcc.empty?
        m.bcc.each_with_index { |p, i| @person_lines[start + addressee_lines.length + from_line.length + i] = p }
        addressee_lines += format_person_list "   Bcc: ", m.bcc
      end

      headers = OrderedHash.new
      headers["Date"] = "#{m.date.strftime DATE_FORMAT} (#{m.date.to_nice_distance_s})"
      headers["Subject"] = m.subj

      show_labels = @thread.labels - LabelManager::HIDDEN_RESERVED_LABELS
      unless show_labels.empty?
        headers["Labels"] = show_labels.map { |x| x.to_s }.sort.join(', ')
      end
      if parent
        headers["In reply to"] = "#{parent.from.mediumname}'s message of #{parent.date.strftime DATE_FORMAT}"
      end

      HookManager.run "detailed-headers", :message => m, :headers => headers

      from_line + (addressee_lines + headers.map { |k, v| "   #{k}: #{v}" }).map { |l| [[color, prefix + "  " + l]] }
    end
  end

  def format_person_list prefix, people
    ptext = people.map { |p| format_person p }
    pad = " " * prefix.display_length
    [prefix + ptext.first + (ptext.length > 1 ? "," : "")] +
      ptext[1 .. -1].map_with_index do |e, i|
        pad + e + (i == ptext.length - 1 ? "" : ",")
      end
  end

  def format_person p
    p.longname + (ContactManager.is_aliased_contact?(p) ? " (#{ContactManager.alias_for p})" : "")
  end

  ## todo: check arguments on this overly complex function
  def chunk_to_lines chunk, state, start, depth, parent=nil, color=nil, star_color=nil
    prefix = " " * INDENT_SPACES * depth
    case chunk
    when :fake_root
      [[[:missing_message_color, "#{prefix}<one or more unreceived messages>"]]]
    when nil
      [[[:missing_message_color, "#{prefix}<an unreceived message>"]]]
    when Message
      message_patina_lines(chunk, state, start, parent, prefix, color, star_color) +
        (chunk.is_draft? ? [[[:draft_notification_color, prefix + " >>> #{m('thread_view.draft_notice')} <<<"]]] : [])

    else
      raise "Bad chunk: #{chunk.inspect}" unless chunk.respond_to?(:inlineable?) ## debugging
      if chunk.inlineable?
        chunk.lines.map { |line| [[chunk.color, "#{prefix}#{line}"]] }
      elsif chunk.expandable?
        case state
        when :closed
          [[[chunk.patina_color, "#{prefix}+ #{chunk.patina_text}"]]]
        when :open
          [[[chunk.patina_color, "#{prefix}- #{chunk.patina_text}"]]] + chunk.lines.map { |line| [[chunk.color, "#{prefix}#{line}"]] }
        end
      else
        [[[chunk.patina_color, "#{prefix}x #{chunk.patina_text}"]]]
      end
    end
  end

  def view chunk
    BufferManager.flash m('flash.info.viewing_attachment', :content_type => chunk.content_type)
    success = chunk.view!
    BufferManager.erase_flash
    BufferManager.completely_redraw_screen
    unless success
      BufferManager.spawn "#{m('words.attachment')}: #{chunk.filename}", TextMode.new(chunk.to_s, chunk.filename)
      BufferManager.flash m('flash.info.couldnt_exec_view_cmd')
    end
  end
end

end
