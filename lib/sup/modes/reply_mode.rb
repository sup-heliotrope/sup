module Redwood

class ReplyMode < EditMessageMode
  REPLY_TYPES = [:sender, :recipient, :list, :all, :user]
  TYPE_DESCRIPTIONS = {
    :sender => "Sender",
    :recipient => "Recipient",
    :all => "All",
    :list => "Mailing list",
    :user => "Customized"
  }

  HookManager.register "attribution", <<EOS
Generates an attribution ("Excerpts from Joe Bloggs's message of Fri Jan 11 09:54:32 -0500 2008:").
Variables:
  message: a message object representing the message being replied to
    (useful values include message.from.name and message.date)
Return value:
  A string containing the text of the quote line (can be multi-line)
EOS

  HookManager.register "reply-from", <<EOS
Selects a default address for the From: header of a new reply.
Variables:
  message: a message object representing the message being replied to
    (useful values include message.recipient_email, message.to, and message.cc)
Return value:
  A Person to be used as the default for the From: header, or nil to use the
  default behavior.
EOS

  HookManager.register "reply-to", <<EOS
Set the default reply-to mode.
Variables:
  modes: array of valid modes to choose from, which will be a subset of
             [:#{REPLY_TYPES * ', :'}]
         The default behavior is equivalent to
             ([:list, :sender, :recipent] & modes)[0]
Return value:
  The reply mode you desire, or nil to use the default behavior.
EOS

  def initialize message, type_arg=nil
    @m = message
    @edited = false

    ## it's important to put this early because it forces a read of
    ## the full headers (most importantly the list-post header, if
    ## any)
    body = reply_body_lines message
    @body_orig = body

    ## first, determine the address at which we received this email. this will
    ## become our From: address in the reply.
    hook_reply_from = HookManager.run "reply-from", :message => @m

    ## sanity check that selection is a Person (or we'll fail below)
    ## don't check that it's an Account, though; assume they know what they're
    ## doing.
    if hook_reply_from && !(hook_reply_from.is_a? Person)
      info "reply-from returned non-Person, using default from."
      hook_reply_from = nil
    end

    ## determine the from address of a reply.
    ## if we have a value from a hook, use it.
    from = if hook_reply_from
      hook_reply_from
    ## otherwise, try and find an account somewhere in the list of to's
    ## and cc's and look up the corresponding name form the list of accounts.
    ## if this does not succeed use the recipient_email (=envelope-to) instead.
    ## this is for the case where mail is received from a mailing lists (so the
    ## To: is the list id itself). if the user subscribes via a particular
    ## alias, we want to use that alias in the reply.
    elsif(b = (@m.to.collect {|t| t.email} + @m.cc.collect {|c| c.email} + [@m.recipient_email] ).find { |p| AccountManager.is_account_email? p })
      a = AccountManager.account_for(b)
      Person.new a.name, b
    ## if all else fails, use the default
    else
      AccountManager.default_account
    end

    ## now, determine to: and cc: addressess. we ignore reply-to for list
    ## messages because it's typically set to the list address, which we
    ## explicitly treat with reply type :list
    to = @m.is_list_message? ? @m.from : (@m.replyto || @m.from)

    ## next, cc:
    cc = (@m.to + @m.cc - [from, to]).uniq

    if to.full_address == "sup@fake.sender.example.com"
    	to = nil
    end

    ## one potential reply type is "reply to recipient". this only happens
    ## in certain cases:
    ## if there's no cc, then the sender is the person you want to reply
    ## to. if it's a list message, then the list address is. otherwise,
    ## the cc contains a recipient.
    useful_recipient = !(cc.empty? || @m.is_list_message?)

    @headers = {}
    @headers[:recipient] = {
      "To" => (cc.map { |p| p.full_address == "sup@fake.sender.example.com" ? nil : p.full_address}.compact),
      "Cc" => [],
    } if useful_recipient

    ## typically we don't want to have a reply-to-sender option if the sender
    ## is a user account. however, if the cc is empty, it's a message to
    ## ourselves, so for the lack of any other options, we'll add it.
    @headers[:sender] = {
      "To" => [to.full_address],
      "Cc" => [],
    } if !AccountManager.is_account?(to) && !useful_recipient && !to.full_address == "sup@fake.sender.example.com"

    @headers[:user] = {
      "To" => [],
      "Cc" => [],
    }

    not_me_ccs = cc.select { |p| !AccountManager.is_account?(p) }
    @headers[:all] = {
      "To" => [to.full_address],
      "Cc" => (not_me_ccs.map { |p| p.full_address == "sup@fake.sender.example.com" ? nil : p.full_address }.compact),
    } if !not_me_ccs.empty? && !to.full_address == "sup@fake.sender.example.com"

    @headers[:list] = {
      "To" => [@m.list_address.full_address],
      "Cc" => [],
    } if @m.is_list_message?

    refs = gen_references

    types = REPLY_TYPES.select { |t| @headers.member?(t) }
    @type_selector = HorizontalSelector.new "Reply to:", types, types.map { |x| TYPE_DESCRIPTIONS[x] }

    hook_reply = HookManager.run "reply-to", :modes => types

    @type_selector.set_to(
      if types.include? type_arg
        type_arg
      elsif types.include? hook_reply
        hook_reply
      elsif @m.is_list_message?
        :list
      elsif @headers.member? :sender
        :sender
      else
        :user
      end)

    headers_full = {
      "From" => from.full_address,
      "Bcc" => [],
      "In-reply-to" => "<#{@m.id}>",
      "Subject" => Message.reify_subj(@m.subj),
      "References" => refs,
    }.merge @headers[@type_selector.val]

    HookManager.run "before-edit", :header => headers_full, :body => body

    super :header => headers_full, :body => body, :twiddles => false
    add_selector @type_selector
  end

protected

  def move_cursor_right
    super
    if @headers[@type_selector.val] != self.header
      self.header = self.header.merge @headers[@type_selector.val]
      rerun_crypto_selector_hook
      update
    end
  end

  def move_cursor_left
    super
    if @headers[@type_selector.val] != self.header
      self.header = self.header.merge @headers[@type_selector.val]
      rerun_crypto_selector_hook
      update
    end
  end

  def reply_body_lines m
    attribution = HookManager.run("attribution", :message => m) || default_attribution(m)
    lines = attribution.split("\n") + m.quotable_body_lines.map { |l| "> #{l}" }
    lines.pop while lines.last =~ /^\s*$/
    lines
  end

  def default_attribution m
    "Excerpts from #{@m.from.name}'s message of #{@m.date}:"
  end

  def handle_new_text new_header, new_body
    if new_body != @body_orig
      @body_orig = new_body
      @edited = true
    end
    old_header = @headers[@type_selector.val]
    if old_header.any? { |k, v| new_header[k] != v }
      @type_selector.set_to :user
      self.header["To"] = @headers[:user]["To"] = new_header["To"]
      self.header["Cc"] = @headers[:user]["Cc"] = new_header["Cc"]
      update
    end
  end

  def gen_references
    (@m.refs + [@m.id]).map { |x| "<#{x}>" }.join(" ")
  end

  def edit_field field
    edited_field = super
    if edited_field and (field == "To" or field == "Cc")
      @type_selector.set_to :user
      @headers[:user]["To"] = self.header["To"]
      @headers[:user]["Cc"] = self.header["Cc"]
      update
    end
  end

  def send_message
    return unless super # super returns true if the mail has been sent
    @m.add_label :replied
    Index.save_message @m
  end
end

end
