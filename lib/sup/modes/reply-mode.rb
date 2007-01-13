module Redwood

class ReplyMode < EditMessageMode
  REPLY_TYPES = [:sender, :recipient, :list, :all, :user]
  TYPE_DESCRIPTIONS = {
    :sender => "Reply to sender",
    :recipient => "Reply to recipient",
    :all => "Reply to all",
    :list => "Reply to mailing list",
    :user => "Customized reply"
  }

  register_keymap do |k|
    k.add :move_cursor_right, "Move cursor to the right", :right
    k.add :move_cursor_left, "Move cursor to the left", :left
  end

  def initialize message
    super 2, :twiddles => false
    @m = message

    ## it's important to put this early because it forces a read of
    ## the full headers (most importantly the list-post header, if
    ## any)
    @body = reply_body_lines(message)

    from =
      if @m.recipient_email
        AccountManager.account_for(@m.recipient_email)
      else
        (@m.to + @m.cc).find { |p| AccountManager.is_account? p }
      end || AccountManager.default_account

    #from_email = @m.recipient_email || from.email
    from_email = from.email

    ## ignore reply-to for list messages because it's typically set to
    ## the list address anyways
    to = @m.is_list_message? ? @m.from : (@m.replyto || @m.from)
    cc = (@m.to + @m.cc - [from, to]).uniq

    @headers = {}
    @headers[:sender] = {
      "From" => "#{from.name} <#{from_email}>",
      "To" => [to.full_address],
    } unless AccountManager.is_account? to

    @headers[:recipient] = {
      "From" => "#{from.name} <#{from_email}>",
      "To" => cc.map { |p| p.full_address },
    } unless cc.empty? || @m.is_list_message?

    @headers[:user] = {
      "From" => "#{from.name} <#{from_email}>",
    }

    @headers[:all] = {
      "From" => "#{from.name} <#{from_email}>",
      "To" => [to.full_address],
      "Cc" => cc.map { |p| p.full_address },
    } unless cc.empty?

    @headers[:list] = {
      "From" => "#{from.name} <#{from_email}>",
      "To" => [@m.list_address.full_address],
    } if @m.is_list_message?

    refs = gen_references
    mid = gen_message_id
    @headers.each do |k, v|
      @headers[k] = {
               "To" => "",
               "Cc" => "",
               "Bcc" => "",
               "In-Reply-To" => "<#{@m.id}>",
               "Subject" => Message.reify_subj(@m.subj),
               "Message-Id" => mid,
               "References" => refs,
             }.merge v
    end

    @type_labels = REPLY_TYPES.select { |t| @headers.member?(t) }
    @selected_type = 
      if @m.is_list_message?
        :list
      elsif @headers.member? :sender
        :sender
      else
        :recipient
      end

    @body += sig_lines
    regen_text
  end

  def lines; @text.length + 2; end
  def [] i
    case i
    when 0
      lame = []
      @type_labels.each do |t|
        lame << [(t == @selected_type ? :none_highlight : :none), 
          "#{TYPE_DESCRIPTIONS[t]}"]
        lame << [:none, "  "]
      end
      lame + [[:none, ""]]
    when 1
      ""
    else
      @text[i - 2]
    end
  end

protected

  def body; @body; end
  def header; @headers[@selected_type]; end

  def reply_body_lines m
    lines = ["Excerpts from #{@m.from.name}'s message of #{@m.date}:"] + 
      m.basic_body_lines.map { |l| "> #{l}" }
    lines.pop while lines.last !~ /[:alpha:]/
    lines
  end

  def handle_new_text new_header, new_body
    @body = new_body

    if new_header.size != header.size ||
        header.any? { |k, v| new_header[k] != v }
      #raise "nhs: #{new_header.size} hs: #{header.size} new: #{new_header.inspect} old: #{header.inspect}"
      @selected_type = :user
      @headers[:user] = new_header
    end
  end

  def regen_text
    @text = header_lines(header - NON_EDITABLE_HEADERS) + [""] + body
  end

  def gen_references
    (@m.refs + [@m.id]).map { |x| "<#{x}>" }.join(" ")
  end
  
  def move_cursor_left
    i = @type_labels.index @selected_type
    @selected_type = @type_labels[(i - 1) % @type_labels.length]
    update
  end

  def move_cursor_right
    i = @type_labels.index @selected_type
    @selected_type = @type_labels[(i + 1) % @type_labels.length]
    update
  end
end

end
