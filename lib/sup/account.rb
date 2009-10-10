module Redwood

class Account < Person
  attr_accessor :sendmail, :signature

  def initialize h
    raise ArgumentError, "no name for account" unless h[:name]
    raise ArgumentError, "no email for account" unless h[:email]
    super h[:name], h[:email]
    @sendmail = h[:sendmail]
    @signature = h[:signature]
  end

  # Default sendmail command for bouncing mail,
  # deduced from #sendmail
  def bounce_sendmail
    sendmail.sub(/\s(\-(ti|it|t))\b/) do |match|
      case $1
      when '-t' then ''
      else ' -i'
      end
    end
  end
end

class AccountManager
  include Singleton

  attr_accessor :default_account

  def initialize accounts
    @email_map = {}
    @accounts = {}
    @regexen = {}
    @default_account = nil

    add_account accounts[:default], true
    accounts.each { |k, v| add_account v, false unless k == :default }
  end

  def user_accounts; @accounts.keys; end
  def user_emails; @email_map.keys.select { |e| String === e }; end

  ## must be called first with the default account. fills in missing
  ## values from the default account.
  def add_account hash, default=false
    raise ArgumentError, "no email specified for account" unless hash[:email]
    unless default
      [:name, :sendmail, :signature].each { |k| hash[k] ||= @default_account.send(k) }
    end
    hash[:alternates] ||= []

    a = Account.new hash
    @accounts[a] = true

    if default
      raise ArgumentError, "multiple default accounts" if @default_account
      @default_account = a
    end

    ([hash[:email]] + hash[:alternates]).each do |email|
      next if @email_map.member? email
      @email_map[email] = a
    end

    hash[:regexen].each do |re|
      @regexen[Regexp.new(re)] = a
    end if hash[:regexen]
  end

  def is_account? p; is_account_email? p.email end
  def is_account_email? email; !account_for(email).nil? end
  def account_for email
    if(a = @email_map[email])
      a
    else
      @regexen.argfind { |re, a| re =~ email && a }
    end
  end
end

end
