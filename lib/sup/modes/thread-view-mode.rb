module Redwood

class ThreadViewMode < LineCursorMode
  ## this holds all info we need to lay out a message
  class Layout
    attr_accessor :top, :bot, :prev, :next, :depth, :width, :state, :color, :star_color, :orig_new
  end

  DATE_FORMAT = "%B %e %Y %l:%M%P"
  INDENT_SPACES = 2 # how many spaces to indent child messages

  register_keymap do |k|
    k.add :toggle_detailed_header, "Toggle detailed header", 'd'
    k.add :show_header, "Show full message header", 'H'
    k.add :toggle_expanded, "Expand/collapse item", :enter
    k.add :expand_all_messages, "Expand/collapse all messages", 'E'
    k.add :edit_message, "Edit message (drafts only)", 'e'
    k.add :expand_all_quotes, "Expand/collapse all quotes in a message", 'o'
    k.add :jump_to_next_open, "Jump to next open message", 'n'
    k.add :jump_to_prev_open, "Jump to previous open message", 'p'
    k.add :toggle_starred, "Star or unstar message", '*'
    k.add :collapse_non_new_messages, "Collapse all but new messages", 'N'
    k.add :reply, "Reply to a message", 'r'
    k.add :forward, "Forward a message", 'f'
    k.add :alias, "Edit alias/nickname for a person", 'a'
    k.add :edit_as_new, "Edit message as new", 'D'
    k.add :save_to_disk, "Save message/attachment to disk", 's'
    k.add :search, "Search for messages from particular people", 'S'
    k.add :compose, "Compose message to person", 'm'
    k.add :archive_and_kill, "Archive thread and kill buffer", 'A'
  end

  ## there are a couple important instance variables we hold to lay
  ## out the thread and to provide line-based functionality. @layout
  ## is a map from Message and Chunk objects to Layout objects. (for
  ## chunks, we only use the state field right now.) @message_lines is
  ## a map from row #s to Message objects. @chunk_lines is a map from
  ## row #s to Chunk objects. @person_lines is a map from row #s to
  ## Person objects.

  def initialize thread, hidden_labels=[]
    super()
    @thread = thread
    @hidden_labels = hidden_labels

    @layout = {}
    earliest, latest = nil, nil
    latest_date = nil
    altcolor = false
    @thread.each do |m, d, p|
      next unless m
      earliest ||= m
      @layout[m] = Layout.new
      @layout[m].state = initial_state_for m
      @layout[m].color = altcolor ? :alternate_patina_color : :message_patina_color
      @layout[m].star_color = altcolor ? :alternate_starred_patina_color : :starred_patina_color
      @layout[m].orig_new = m.has_label? :unread
      altcolor = !altcolor
      if latest_date.nil? || m.date > latest_date
        latest_date = m.date
        latest = m
      end
    end

    @layout[latest].state = :open if @layout[latest].state == :closed
    @layout[earliest].state = :detailed if earliest.has_label?(:unread) || @thread.size == 1

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
    BufferManager.spawn_unless_exists("Full header") do
      TextMode.new m.raw_header
    end
  end

  def toggle_detailed_header
    m = @message_lines[curpos] or return
    @layout[m].state = (@layout[m].state == :detailed ? :open : :detailed)
    update
  end

  def reply
    m = @message_lines[curpos] or return
    mode = ReplyMode.new m
    BufferManager.spawn "Reply to #{m.subj}", mode
  end

  def forward
    m = @message_lines[curpos] or return
    mode = ForwardMode.new m
    BufferManager.spawn "Forward of #{m.subj}", mode
    mode.edit
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
    p = @person_lines[curpos] or return
    mode = ComposeMode.new :to => [p]
    BufferManager.spawn "Message to #{p.name}", mode
    mode.edit
  end    

  def toggle_starred
    m = @message_lines[curpos] or return
    if m.has_label? :starred
      m.remove_label :starred
    else
      m.add_label :starred
    end
    ## TODO: don't recalculate EVERYTHING just to add a stupid little
    ## star to the display
    update
    UpdateManager.relay self, :starred, m
  end

  def toggle_expanded
    chunk = @chunk_lines[curpos] or return
    case chunk
    when Message, Message::Quote, Message::Signature
      return if chunk.lines.length == 1 unless chunk.is_a? Message # too small to expand/close
      l = @layout[chunk]
      l.state = (l.state != :closed ? :closed : :open)
      cursor_down if l.state == :closed
    when Message::Attachment
      view_attachment chunk
    end
    update
  end

  def edit_as_new
    m = @message_lines[curpos] or return
    mode = ComposeMode.new(:body => m.basic_body_lines, :to => m.to, :cc => m.cc, :subj => m.subj, :bcc => m.bcc)
    BufferManager.spawn "edit as new", mode
    mode.edit
  end

  def save_to_disk
    chunk = @chunk_lines[curpos] or return
    case chunk
    when Message::Attachment
      fn = BufferManager.ask :filename, "Save attachment to file: ", chunk.filename
      save_to_file(fn) { |f| f.print chunk } if fn
    else
      m = @message_lines[curpos]
      fn = BufferManager.ask :filename, "Save message to file: "
      save_to_file(fn) { |f| f.print m.raw_full_message } if fn
    end
  end

  def edit_message
    m = @message_lines[curpos] or return
    if m.is_draft?
      mode = ResumeMode.new m
      BufferManager.spawn "Edit message", mode
      mode.edit
    else
      BufferManager.flash "Not a draft message!"
    end
  end

  def jump_to_first_open
    m = @message_lines[0] or return
    if @layout[m].state != :closed
      jump_to_message m
    else
      jump_to_next_open
    end
  end

  def jump_to_next_open
    m = @message_lines[curpos] or return
    while nextm = @layout[m].next
      break if @layout[nextm].state != :closed
      m = nextm
    end
    jump_to_message nextm if nextm
  end

  def jump_to_prev_open
    m = @message_lines[curpos] or return
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

  def jump_to_message m
    l = @layout[m]
    left = l.depth * INDENT_SPACES
    right = left + l.width

    ## jump to the top line unless both top and bottom fit in the current view
    jump_to_line l.top unless l.top >= topline && l.top <= botline && l.bot >= topline && l.bot <= botline

    ## jump to the left columns unless both left and right fit in the current view
    jump_to_col left unless left >= leftcol && left <= rightcol && right >= leftcol && right <= rightcol

    ## either way, move the cursor to the first line
    set_cursor_pos l.top
  end

  def expand_all_messages
    @global_message_state ||= :closed
    @global_message_state = (@global_message_state == :closed ? :open : :closed)
    @layout.each { |m, l| l.state = @global_message_state if m.is_a? Message }
    update
  end

  def collapse_non_new_messages
    @layout.each { |m, l| l.state = l.orig_new ? :open : :closed if m.is_a? Message }
    update
  end

  def expand_all_quotes
    if(m = @message_lines[curpos])
      quotes = m.chunks.select { |c| (c.is_a?(Message::Quote) || c.is_a?(Message::Signature)) && c.lines.length > 1 }
      numopen = quotes.inject(0) { |s, c| s + (@layout[c].state == :open ? 1 : 0) }
      newstate = numopen > quotes.length / 2 ? :closed : :open
      quotes.each { |c| @layout[c].state = newstate }
      update
    end
  end

  def cleanup
    @layout = @text = nil # for good luck
  end

  def archive_and_kill
    @thread.remove_label :inbox
    UpdateManager.relay self, :archived, @thread
    BufferManager.kill_buffer_safely buffer
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
      l = @layout[m] or next # TODO: figure out why this is nil sometimes

      ## build the patina
      text = chunk_to_lines m, l.state, @text.length, depth, parent, @layout[m].color, @layout[m].star_color
      
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
        lw = text[i].flatten.select { |x| x.is_a? String }.map { |x| x.length }.sum
      end

      @text += text
      prevm = m 
      if @layout[m].state != :closed
        m.chunks.each do |c|
          cl = (@layout[c] ||= Layout.new)
          cl.state ||= :closed
          text = chunk_to_lines c, cl.state, @text.length, depth
          (0 ... text.length).each do |i|
            @chunk_lines[@text.length + i] = c
            @message_lines[@text.length + i] = m
            lw = text[i].flatten.select { |x| x.is_a? String }.map { |x| x.length }.sum - (depth * INDENT_SPACES)
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
    widget = 
      case state
      when :closed
        [color, "+ "]
      when :open, :detailed
        [color, "- "]
      end
    imp_widget = 
      if m.has_label?(:starred)
        [star_color, "* "]
      else
        [color, "  "]
      end

    case state
    when :open
      @person_lines[start] = m.from
      [[prefix_widget, widget, imp_widget,
        [color, 
            "#{m.from ? m.from.mediumname : '?'} to #{m.recipients.map { |l| l.shortname }.join(', ')} #{m.date.to_nice_s} (#{m.date.to_nice_distance_s})"]]]

    when :closed
      @person_lines[start] = m.from
      [[prefix_widget, widget, imp_widget,
        [color, 
        "#{m.from ? m.from.mediumname : '?'}, #{m.date.to_nice_s} (#{m.date.to_nice_distance_s})  #{m.snippet}"]]]

    when :detailed
      @person_lines[start] = m.from
      from = [[prefix_widget, widget, imp_widget, [color, "From: #{m.from ? format_person(m.from) : '?'}"]]]

      rest = []
      unless m.to.empty?
        m.to.each_with_index { |p, i| @person_lines[start + rest.length + from.length + i] = p }
        rest += format_person_list "  To: ", m.to
      end
      unless m.cc.empty?
        m.cc.each_with_index { |p, i| @person_lines[start + rest.length + from.length + i] = p }
        rest += format_person_list "  Cc: ", m.cc
      end
      unless m.bcc.empty?
        m.bcc.each_with_index { |p, i| @person_lines[start + rest.length + from.length + i] = p }
        rest += format_person_list "  Bcc: ", m.bcc
      end

      rest += [
        "  Date: #{m.date.strftime DATE_FORMAT} (#{m.date.to_nice_distance_s})",
        "  Subject: #{m.subj}",
        (parent ? "  In reply to: #{parent.from.mediumname}'s message of #{parent.date.strftime DATE_FORMAT}" : nil),
        m.labels.empty? ? nil : "  Labels: #{m.labels.join(', ')}",
      ].compact
      
      from + rest.map { |l| [[color, prefix + "  " + l]] }
    end
  end

  def format_person_list prefix, people
    ptext = people.map { |p| format_person p }
    pad = " " * prefix.length
    [prefix + ptext.first + (ptext.length > 1 ? "," : "")] + 
      ptext[1 .. -1].map_with_index do |e, i|
        pad + e + (i == ptext.length - 1 ? "" : ",")
      end
  end

  def format_person p
    p.longname + (ContactManager.is_contact?(p) ? " (#{ContactManager.alias_for p})" : "")
  end

  def chunk_to_lines chunk, state, start, depth, parent=nil, color=nil, star_color=nil
    prefix = " " * INDENT_SPACES * depth
    case chunk
    when :fake_root
      [[[:missing_message_color, "#{prefix}<one or more unreceived messages>"]]]
    when nil
      [[[:missing_message_color, "#{prefix}<an unreceived message>"]]]
    when Message
      message_patina_lines(chunk, state, start, parent, prefix, color, star_color) +
        (chunk.is_draft? ? [[[:draft_notification_color, prefix + " >>> This message is a draft. To edit, hit 'e'. <<<"]]] : [])
    when Message::Attachment
      [[[:mime_color, "#{prefix}+ MIME attachment #{chunk.content_type}#{chunk.desc ? ' (' + chunk.desc + ')': ''}"]]]
    when Message::Text
      t = chunk.lines
      if t.last =~ /^\s*$/ && t.length > 1
        t.pop while t[-2] =~ /^\s*$/ # pop until only one file empty line
      end
      t.map { |line| [[:none, "#{prefix}#{line}"]] }
    when Message::Quote
      return [[[:quote_color, "#{prefix}#{chunk.lines.first}"]]] if chunk.lines.length == 1
      case state
      when :closed
        [[[:quote_patina_color, "#{prefix}+ (#{chunk.lines.length} quoted lines)"]]]
      when :open
        [[[:quote_patina_color, "#{prefix}- (#{chunk.lines.length} quoted lines)"]]] + chunk.lines.map { |line| [[:quote_color, "#{prefix}#{line}"]] }
      end
    when Message::Signature
      return [[[:sig_patina_color, "#{prefix}#{chunk.lines.first}"]]] if chunk.lines.length == 1
      case state
      when :closed
        [[[:sig_patina_color, "#{prefix}+ (#{chunk.lines.length}-line signature)"]]]
      when :open
        [[[:sig_patina_color, "#{prefix}- (#{chunk.lines.length}-line signature)"]]] + chunk.lines.map { |line| [[:sig_color, "#{prefix}#{line}"]] }
      end
    else
      raise "unknown chunk type #{chunk.class.name}"
    end
  end

  def view_attachment a
    BufferManager.flash "viewing #{a.content_type} attachment..."
    success = a.view!
    BufferManager.erase_flash
    BufferManager.completely_redraw_screen
    BufferManager.flash "Couldn't execute view command." unless success
  end

end

end
