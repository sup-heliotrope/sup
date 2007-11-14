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
    @m = message

    ## it's important to put this early because it forces a read of
    ## the full headers (most importantly the list-post header, if
    ## any)
    body = reply_body_lines message

    from =
      if @m.recipient_email && (a = AccountManager.account_for(@m.recipient_email))
        a
      elsif(b = (@m.to + @m.cc).find { |p| AccountManager.is_account? p })
        b
      else
        AccountManager.default_account
      end

    ## ignore reply-to for list messages because it's typically set to
    ## the list address, which we explicitly treat with :list
    to = @m.is_list_message? ? @m.from : (@m.replyto || @m.from)
    cc = (@m.to + @m.cc - [from, to]).uniq

    @headers = {}

    ## if there's no cc, then the sender is the person you want to reply
    ## to. if it's a list message, then the list address is. otherwise,
    ## the cc contains a recipient.
    useful_recipient = !(cc.empty? || @m.is_list_message?)
    
    @headers[:recipient] = {
      "To" => cc.map { |p| p.full_address },
    } if useful_recipient

    ## typically we don't want to have a reply-to-sender option if the sender
    ## is a user account. however, if the cc is empty, it's a message to
    ## ourselves, so for the lack of any other options, we'll add it.
    @headers[:sender] = { "To" => [to.full_address], } if !AccountManager.is_account?(to) || !useful_recipient

    @headers[:user] = {}

    @headers[:all] = {
      "To" => [to.full_address],
      "Cc" => cc.select { |p| !AccountManager.is_account?(p) }.map { |p| p.full_address },
    } unless cc.empty?

    @headers[:list] = {
      "To" => [@m.list_address.full_address],
    } if @m.is_list_message?

    refs = gen_references

    @headers.each do |k, v|
      @headers[k] = {
               "From" => "#{from.name} <#{from.email}>",
               "To" => [],
               "Cc" => [],
               "Bcc" => [],
               "In-Reply-To" => "<#{@m.id}>",
               "Subject" => Message.reify_subj(@m.subj),
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

    super :header => @headers[@selected_type], :body => body,
          :skip_top_rows => 2, :twiddles => false
  end

  def lines; super + 2; end
  def [] i
    case i
    when 0
      @type_labels.inject([]) do |array, t|
        array + [[(t == @selected_type ? :none_highlight : :none), 
          "#{TYPE_DESCRIPTIONS[t]}"], [:none, "  "]]
      end + [[:none, ""]]
    when 1
      ""
    else
      super(i - 2)
    end
  end

protected

  def reply_body_lines m
    lines = ["Excerpts from #{@m.from.name}'s message of #{@m.date}:"] + 
      m.basic_body_lines.map { |l| "> #{l}" }
    lines.pop while lines.last =~ /^\s*$/
    lines
  end

  def handle_new_text new_header, new_body
    old_header = @headers[@selected_type]
    if new_header.size != old_header.size || old_header.any? { |k, v| new_header[k] != v }
      @selected_type = :user
      self.header = @headers[:user] = new_header
      update
    end
  end

  def gen_references
    (@m.refs + [@m.id]).map { |x| "<#{x}>" }.join(" ")
  end

  def edit_field field
    edited_field = super
    if edited_field && edited_field != "Subject"
      @selected_type = :user
      update
    end
  end
  
  def move_cursor_left
    i = @type_labels.index @selected_type
    @selected_type = @type_labels[(i - 1) % @type_labels.length]
    self.header = @headers[@selected_type]
    update
  end

  def move_cursor_right
    i = @type_labels.index @selected_type
    @selected_type = @type_labels[(i + 1) % @type_labels.length]
    self.header = @headers[@selected_type]
    update
  end
end

end
