module Redwood

class ThreadViewMode < LineCursorMode
  ## this holds all info we need to lay out a message
  class MessageLayout
    attr_accessor :top, :bot, :prev, :next, :depth, :width, :state, :color, :star_color, :orig_new
  end

  class ChunkLayout
    attr_accessor :state
  end

  DATE_FORMAT = "%B %e %Y %l:%M%p"
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
    k.add :toggle_detailed_header, "Toggle detailed header", 'h'
    k.add :show_header, "Show full message header", 'H'
    k.add :show_message, "Show full message (raw form)", 'V'
    k.add :activate_chunk, "Expand/collapse or activate item", :enter
    k.add :expand_all_messages, "Expand/collapse all messages", 'E'
    k.add :edit_draft, "Edit draft", 'e'
    k.add :send_draft, "Send draft", 'y'
    k.add :edit_labels, "Edit or add labels for a thread", 'l'
    k.add :expand_all_quotes, "Expand/collapse all quotes in a message", 'o'
    k.add :jump_to_next_open, "Jump to next open message", 'n'
    k.add :jump_to_prev_open, "Jump to previous open message", 'p'
    k.add :align_current_message, "Align current message in buffer", 'z'
    k.add :toggle_starred, "Star or unstar message", '*'
    k.add :toggle_new, "Toggle unread/read status of message", 'N'
#    k.add :collapse_non_new_messages, "Collapse all but unread messages", 'N'
    k.add :reply, "Reply to a message", 'r'
    k.add :reply_all, "Reply to all participants of this message", 'G'
    k.add :forward, "Forward a message or attachment", 'f'
    k.add :bounce, "Bounce message to other recipient(s)", '!'
    k.add :alias, "Edit alias/nickname for a person", 'i'
    k.add :edit_as_new, "Edit message as new", 'D'
    k.add :save_to_disk, "Save message/attachment to disk", 's'
    k.add :search, "Search for messages from particular people", 'S'
    k.add :compose, "Compose message to person", 'm'
    k.add :subscribe_to_list, "Subscribe to/unsubscribe from mailing list", "("
    k.add :unsubscribe_from_list, "Subscribe to/unsubscribe from mailing list", ")"
    k.add :pipe_message, "Pipe message or attachment to a shell command", '|'

    k.add :archive_and_next, "Archive this thread, kill buffer, and view next", 'a'
    k.add :delete_and_next, "Delete this thread, kill buffer, and view next", 'd'

    k.add_multi "(a)rchive/(d)elete/mark as (s)pam/mark as u(N)read:", '.' do |kk|
      kk.add :archive_and_kill, "Archive this thread and kill buffer", 'a'
      kk.add :delete_and_kill, "Delete this thread and kill buffer", 'd'
      kk.add :spam_and_kill, "Mark this thread as spam and kill buffer", 's'
      kk.add :unread_and_kill, "Mark this thread as unread and kill buffer", 'N'
    end

    k.add_multi "(a)rchive/(d)elete/mark as (s)pam/mark as u(N)read/do (n)othing:", ',' do |kk|
      kk.add :archive_and_next, "Archive this thread, kill buffer, and view next", 'a'
      kk.add :delete_and_next, "Delete this thread, kill buffer, and view next", 'd'
      kk.add :spam_and_next, "Mark this thread as spam, kill buffer, and view next", 's'
      kk.add :unread_and_next, "Mark this thread as unread, kill buffer, and view next", 'N'
      kk.add :do_nothing_and_next, "Kill buffer, and view next", 'n'
    end

    k.add_multi "(a)rchive/(d)elete/mark as (s)pam/mark as u(N)read/do (n)othing:", ']' do |kk|
      kk.add :archive_and_prev, "Archive this thread, kill buffer, and view previous", 'a'
      kk.add :delete_and_prev, "Delete this thread, kill buffer, and view previous", 'd'
      kk.add :spam_and_prev, "Mark this thread as spam, kill buffer, and view previous", 's'
      kk.add :unread_and_prev, "Mark this thread as unread, kill buffer, and view previous", 'N'
      kk.add :do_nothing_and_prev, "Kill buffer, and view previous", 'n'
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
    BufferManager.spawn_unless_exists("Full header for #{m.id}") do
      TextMode.new m.raw_header
    end
  end

  def show_message
    m = @message_lines[curpos] or return
    BufferManager.spawn_unless_exists("Raw message for #{m.id}") do
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
    BufferManager.spawn "Reply to #{m.subj}", mode
  end

  def reply_all; reply :all; end

  def subscribe_to_list
    m = @message_lines[curpos] or return
    if m.list_subscribe && m.list_subscribe =~ /<mailto:(.*?)(\?subject=(.*?))?>/
      ComposeMode.spawn_nicely :from => AccountManager.account_for(m.recipient_email), :to => [Person.from_address($1)], :subj => ($3 || "subscribe")
    else
      BufferManager.flash "Can't find List-Subscribe header for this message."
    end
  end

  def unsubscribe_from_list
    m = @message_lines[curpos] or return
    if m.list_unsubscribe && m.list_unsubscribe =~ /<mailto:(.*?)(\?subject=(.*?))?>/
      ComposeMode.spawn_nicely :from => AccountManager.account_for(m.recipient_email), :to => [Person.from_address($1)], :subj => ($3 || "unsubscribe")
    else
      BufferManager.flash "Can't find List-Unsubscribe header for this message."
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

    defcmd = AccountManager.default_account.bounce_sendmail

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
        BufferManager.flash "Problem sending mail: #{e.message}"
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
    BufferManager.spawn "Search for #{p.name}", mode
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
    old_labels = @thread.labels
    reserved_labels = old_labels.select { |l| LabelManager::RESERVED_LABELS.include? l }
    new_labels = BufferManager.ask_for_labels :label, "Labels for thread: ", @thread.labels

    return unless new_labels
    @thread.labels = Set.new(reserved_labels) + new_labels
    new_labels.each { |l| LabelManager << l }
    update
    UpdateManager.relay self, :labeled, @thread.first
    UndoManager.register "labeling thread" do
      @thread.labels = old_labels
      UpdateManager.relay self, :labeled, @thread.first
    end
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
      fn = BufferManager.ask_for_filename :filename, "Save attachment to file: ", default_dir
      save_to_file(fn) { |f| f.print chunk.raw_content } if fn
    else
      m = @message_lines[curpos]
      fn = BufferManager.ask_for_filename :filename, "Save message to file: "
      return unless fn
      save_to_file(fn) do |f|
        m.each_raw_message_line { |l| f.print l }
      end
    end
  end

  def edit_draft
    m = @message_lines[curpos] or return
    if m.is_draft?
      mode = ResumeMode.new m
      BufferManager.spawn "Edit message", mode
      BufferManager.kill_buffer self.buffer
      mode.edit_message
    else
      BufferManager.flash "Not a draft message!"
    end
  end

  def send_draft
    m = @message_lines[curpos] or return
    if m.is_draft?
      mode = ResumeMode.new m
      BufferManager.spawn "Send message", mode
      BufferManager.kill_buffer self.buffer
      mode.send_message
    else
      BufferManager.flash "Not a draft message!"
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
      UndoManager.register "archiving 1 thread" do
        @thread.apply_label :inbox
        UpdateManager.relay self, :unarchived, @thread.first
      end
    end
  end

  def spam_and_then op
    dispatch op do
      @thread.apply_label :spam
      UpdateManager.relay self, :spammed, @thread.first
      UndoManager.register "marking 1 thread as spam" do
        @thread.remove_label :spam
        UpdateManager.relay self, :unspammed, @thread.first
      end
    end
  end

  def delete_and_then op
    dispatch op do
      @thread.apply_label :deleted
      UpdateManager.relay self, :deleted, @thread.first
      UndoManager.register "deleting 1 thread" do
        @thread.remove_label :deleted
        UpdateManager.relay self, :undeleted, @thread.first
      end
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

    command = BufferManager.ask(:shell, "pipe command: ")
    return if command.nil? || command.empty?

    output = pipe_to_process(command) do |stream|
      if chunk
        stream.print chunk.raw_content
      else
        message.each_raw_message_line { |l| stream.print l }
      end
    end

    if output
      BufferManager.spawn "Output of '#{command}'", TextMode.new(output)
    else
      BufferManager.flash "'#{command}' done!"
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
        (chunk.is_draft? ? [[[:draft_notification_color, prefix + " >>> This message is a draft. Hit 'e' to edit, 'y' to send. <<<"]]] : [])

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
    BufferManager.flash "viewing #{chunk.content_type} attachment..."
    success = chunk.view!
    BufferManager.erase_flash
    BufferManager.completely_redraw_screen
    unless success
      BufferManager.spawn "Attachment: #{chunk.filename}", TextMode.new(chunk.to_s, chunk.filename)
      BufferManager.flash "Couldn't execute view command, viewing as text."
    end
  end
end

end
