module Redwood

class ThreadViewMode < LineCursorMode
  DATE_FORMAT = "%B %e %Y %l:%M%P"

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
    k.add :save_to_disk, "Save message/attachment to disk", 's'
  end

  def initialize thread, hidden_labels=[]
    super()
    @thread = thread
    @state = {}
    @hidden_labels = hidden_labels

    earliest, latest = nil, nil
    latest_date = nil
    @thread.each do |m, d, p|
      next unless m
      earliest ||= m
      @state[m] = initial_state_for m
      if latest_date.nil? || m.date > latest_date
        latest_date = m.date
        latest = m
      end
    end

    @state[latest] = :open if @state[latest] == :closed
    @state[earliest] = :detailed if earliest.has_label?(:unread) || @thread.size == 1

    BufferManager.say "Loading message bodies..." do
      regen_chunks
      regen_text
    end
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
    return unless(m = @message_lines[curpos])
    BufferManager.spawn_unless_exists("Full header") do
      TextMode.new m.raw_header
    end
  end

  def toggle_detailed_header
    return unless(m = @message_lines[curpos])
    @state[m] = (@state[m] == :detailed ? :open : :detailed)
    update
  end

  def reply
    return unless(m = @message_lines[curpos])
    mode = ReplyMode.new m
    BufferManager.spawn "Reply to #{m.subj}", mode
  end

  def forward
    return unless(m = @message_lines[curpos])
    mode = ForwardMode.new m
    BufferManager.spawn "Forward of #{m.subj}", mode
    mode.edit
  end

  def toggle_starred
    return unless(m = @message_lines[curpos])
    if m.has_label? :starred
      m.remove_label :starred
    else
      m.add_label :starred
    end
    ## TODO: don't recalculate EVERYTHING just to add a stupid little
    ## star to the display
    update
    UpdateManager.relay :starred, m
  end

  def toggle_expanded
    return unless(chunk = @chunk_lines[curpos])
    case chunk
    when Message, Message::Quote, Message::Signature
      @state[chunk] = (@state[chunk] != :closed ? :closed : :open)
      cursor_down if @state[chunk] == :closed
    when Message::Attachment
      view_attachment chunk
    end
    update
  end

  def save fn
    if File.exists? fn
      return unless BufferManager.ask_yes_or_no "File exists. Overwrite?"
    end
    begin
      File.open(fn, "w") { |f| yield f }
      BufferManager.flash "Successfully wrote #{fn}."
    rescue SystemCallError => e
      BufferManager.flash "Error writing to file: #{e.message}"
    end
  end
  private :save

  def save_to_disk
    return unless(chunk = @chunk_lines[curpos])
    case chunk
    when Message::Attachment
      fn = BufferManager.ask :filename, "save attachment to file: ", chunk.filename
      save(fn) { |f| f.print chunk } if fn
    else
      m = @message_lines[curpos]
      fn = BufferManager.ask :filename, "save message to file: "
      save(fn) { |f| f.print m.raw_full_message } if fn
    end
  end

  def edit_message
    return unless(m = @message_lines[curpos])
    if m.is_draft?
      mode = ResumeMode.new m
      BufferManager.spawn "Edit message", mode
      mode.edit
    else
      BufferManager.flash "Not a draft message!"
    end
  end

  def jump_to_next_open
    return unless(m = @message_lines[curpos])
    while nextm = @messages[m][3]
      break if @state[nextm] == :open
      m = nextm
    end
    jump_to_message nextm if nextm
  end

  def jump_to_prev_open
    return unless(m = @message_lines[curpos])
    ## jump to the top of the current message if we're in the body;
    ## otherwise, to the previous message
    top = @messages[m][0]
    if curpos == top
      while(prevm = @messages[m][2])
        break if @state[prevm] != :closed
        m = prevm
      end
      jump_to_message prevm if prevm
    else
      jump_to_message m
    end
  end

  def jump_to_message m
    top, bot, prevm, nextm, depth = @messages[m]
    jump_to_line top unless top >= topline &&
      top <= botline && bot >= topline && bot <= botline
    jump_to_col depth * 2 # sorry!!!! TODO: make this a constant
    set_cursor_pos top
  end

  def expand_all_messages
    @global_message_state ||= :closed
    @global_message_state = (@global_message_state == :closed ? :open : :closed)
    @state.each { |m, v| @state[m] = @global_message_state if m.is_a? Message }
    update
  end


  def collapse_non_new_messages
    @messages.each { |m, v| @state[m] = m.has_label?(:unread) ? :open : :closed }
    update
  end

  def expand_all_quotes
    if(m = @message_lines[curpos])
      quotes = @chunks[m].select { |c| c.is_a?(Message::Quote) || c.is_a?(Message::Signature) }
      open, closed = quotes.partition { |c| @state[c] == :open }
      newstate = open.length > closed.length ? :closed : :open
      quotes.each { |c| @state[c] = newstate }
      update
    end
  end

  ## kinda slow for large threads. TODO: fasterify
  def cleanup
    BufferManager.say "Marking messages as read..." do
      @thread.each do |m, d, p|
        if m && m.has_label?(:unread)
          m.remove_label :unread 
          UpdateManager.relay :read, m
        end
      end
    end
    @messages = @chunks = @text = nil
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

  def regen_chunks
    @chunks = {}
    @thread.each { |m, d, p| @chunks[m] = m.to_chunks if m.is_a?(Message) }
  end
  
  def regen_text
    @text = []
    @chunk_lines = []
    @message_lines = []
    @messages = {}

    prev_m = nil
    @thread.each do |m, depth, parent|
      ## we're occasionally called on @threads that have had messages
      ## added to them since initialization. luckily we regen_text on
      ## the entire thread every time the user does anything besides
      ## scrolling (basically), so we can just slap this on here.
      ##
      ## to pick nits, the niceness that i do in the constructor with
      ## 'latest' might not be valid, but i don't see that as a huge
      ## issue.
      @state[m] ||= initial_state_for m if m

      text = chunk_to_lines m, @state[m], @text.length, depth, parent
      (0 ... text.length).each do |i|
        @chunk_lines[@text.length + i] = m
        @message_lines[@text.length + i] = m
      end

      ## sorry i store all this shit in an array. very, very sorry.
      ## also sorry about the * 2. very, very sorry.
      @messages[m] = [@text.length, @text.length + text.length, prev_m, nil, depth]
      @messages[prev_m][3] = m if prev_m
      prev_m = m if m.is_a? Message

      @text += text
      if @state[m] != :closed && @chunks.member?(m)
        @chunks[m].each do |c|
          @state[c] ||= :closed
          text = chunk_to_lines c, @state[c], @text.length, depth
          (0 ... text.length).each do |i|
            @chunk_lines[@text.length + i] = c
            @message_lines[@text.length + i] = m
          end
          @text += text
        end
        @messages[m][1] = @text.length
      end
    end
  end

  def message_patina_lines m, state, parent, prefix
    prefix_widget = [:message_patina_color, prefix]
    widget = 
      case state
      when :closed
        [:message_patina_color, "+ "]
      when :open, :detailed
        [:message_patina_color, "- "]
      end
    imp_widget = 
      if m.has_label?(:starred)
        [:starred_patina_color, "* "]
      else
        [:message_patina_color, "  "]
      end

    case state
    when :open
      [[prefix_widget, widget, imp_widget,
        [:message_patina_color, 
            "#{m.from ? m.from.mediumname : '?'} to #{m.recipients.map { |l| l.shortname }.join(', ')} #{m.date.to_nice_s} (#{m.date.to_nice_distance_s})"]]]
    when :closed
      [[prefix_widget, widget, imp_widget,
        [:message_patina_color, 
        "#{m.from ? m.from.mediumname : '?'}, #{m.date.to_nice_s} (#{m.date.to_nice_distance_s})  #{m.snippet}"]]]
    when :detailed
      labels = m.labels# - @hidden_labels
      x = [[prefix_widget, widget, imp_widget, [:message_patina_color, "From: #{m.from ? m.from.longname : '?'}"]]] +
        ((m.to.empty? ? [] : break_into_lines("  To: ", m.to.map { |x| x.longname })) +
           (m.cc.empty? ? [] : break_into_lines("  Cc: ", m.cc.map { |x| x.longname })) +
           (m.bcc.empty? ? [] : break_into_lines("  Bcc: ", m.bcc.map { |x| x.longname })) +
           ["  Date: #{m.date.strftime DATE_FORMAT} (#{m.date.to_nice_distance_s})"] +
           ["  Subject: #{m.subj}"] +
           [(parent ? "  In reply to: #{parent.from.mediumname}'s message of #{parent.date.strftime DATE_FORMAT}" : nil)] +
           [labels.empty? ? nil : "  Labels: #{labels.join(', ')}"]
        ).flatten.compact.map { |l| [[:message_patina_color, prefix + "  " + l]] }
      #raise x.inspect
      x
    end
  end

  def break_into_lines prefix, list
    pad = " " * prefix.length
    [prefix + list.first + (list.length > 1 ? "," : "")] + 
      list[1 .. -1].map_with_index do |e, i|
        pad + e + (i == list.length - 1 ? "" : ",")
      end
  end


  def chunk_to_lines chunk, state, start, depth, parent=nil
    prefix = "  " * depth
    case chunk
    when :fake_root
      [[[:message_patina_color, "#{prefix}<one or more unreceived messages>"]]]
    when nil
      [[[:message_patina_color, "#{prefix}<an unreceived message>"]]]
    when Message
      message_patina_lines(chunk, state, parent, prefix) +
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
      case state
      when :closed
        [[[:quote_patina_color, "#{prefix}+ #{chunk.lines.length} quoted lines"]]]
      when :open
        t = chunk.lines
        [[[:quote_patina_color, "#{prefix}- #{chunk.lines.length} quoted lines"]]] +
           t.map { |line| [[:quote_color, "#{prefix}#{line}"]] }
      end
    when Message::Signature
      case state
      when :closed
        [[[:sig_patina_color, "#{prefix}+ #{chunk.lines.length}-line signature"]]]
      when :open
        t = chunk.lines
        [[[:sig_patina_color, "#{prefix}- #{chunk.lines.length}-line signature"]]] +
           t.map { |line| [[:sig_color, "#{prefix}#{line}"]] }
      end
    else
      raise "unknown chunk type #{chunk.class.name}"
    end
  end

  def view_attachment a
    BufferManager.flash "viewing #{a.content_type} attachment..."
    a.view!
    BufferManager.erase_flash
    BufferManager.completely_redraw_screen
  end

end

end
