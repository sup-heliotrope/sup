module Redwood

class Account < Person
  attr_accessor :sendmail, :signature, :gpgkey

  def initialize h
    raise ArgumentError, "no name for account" unless h[:name]
    raise ArgumentError, "no email for account" unless h[:email]
    super h[:name], h[:email]
    @sendmail = h[:sendmail]
    @signature = h[:signature]
    @gpgkey = h[:gpgkey]
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
    @hidden_email_map = {}
    @email_map_dirty = false
    @accounts = {}
    @regexen = {}
    @default_account = nil

    add_account accounts[:default], true
    accounts.each { |k, v| add_account v, false unless k == :default }
  end

  def user_accounts; @accounts.keys; end
  def user_emails(type = :all); email_map(type).keys.select { |e| String === e }; end

  ## must be called first with the default account. fills in missing
  ## values from the default account.
  def add_account hash, default=false
    raise ArgumentError, "no email specified for account" unless hash[:email]
    unless default
      [:name, :sendmail, :signature, :gpgkey].each { |k| hash[k] ||= @default_account.send(k) }
    end
    hash[:alternates] ||= []
    hash[:hidden_alternates] ||= []
    fail "alternative emails are not an array: #{hash[:alternates]}" unless hash[:alternates].kind_of? Array
    fail "hidden alternative emails are not an array: #{hash[:hidden_alternates]}" unless hash[:hidden_alternates].kind_of? Array

    [:name, :signature].each { |x| hash[x] ? hash[x].fix_encoding! : nil }

    a = Account.new hash
    @accounts[a] = true

    if default
      raise ArgumentError, "multiple default accounts" if @default_account
      @default_account = a
    end

    ([hash[:email]] + hash[:alternates]).each do |email|
      add_email_to_map(:shown, email, a)
    end

    hash[:hidden_alternates].each do |email|
      add_email_to_map(:hidden, email, a)
    end

    hash[:regexen].each do |re|
      @regexen[Regexp.new(re)] = a
    end if hash[:regexen]
  end

  def is_account? p;    is_account_email? p.email       end
  def is_account_email? email; !account_for(email).nil? end

  def account_for email
    a = email_map[email]
    a.nil? ? @regexen.argfind { |re, a| re =~ email && a } : a
  end

  def full_address_for email
    a = account_for email
    Person.full_address a.name, email
  end

  private

  def add_email_to_map(type, email, acc)
    type = :shown if type != :hidden
    m = email_map(type)
    unless m.member? email
      m[email] = acc
      @email_map_dirty = true
    end
  end

  def email_map(type = nil)
    case type
    when :shown, :public  then @email_map
    when :hidden          then @hidden_email_map
    else
      if @email_map_dirty
        @email_map_all = @hidden_email_map.merge(@email_map)
        if @email_map_all.count != @email_map.count + @hidden_email_map.count
          @hidden_email_map.reject! { |m| @email_map.member? m }
        end
      end
      @email_map_all ||= {}
    end
  end
end # class AccountManager

end
