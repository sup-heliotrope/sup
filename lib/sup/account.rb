module Redwood

class Account < Person
  attr_accessor :sendmail, :sig_file

  def initialize h
    super h[:name], h[:email]
    @sendmail = h[:sendmail]
    @sig_file = h[:signature]
  end
end

class AccountManager
  include Singleton

  attr_accessor :default_account

  def initialize accounts
    @email_map = {}
    @alternate_map = {}
    @accounts = {}
    @default_account = nil

    accounts.each { |k, v| add_account v, k == :default }

    self.class.i_am_the_instance self
  end

  def user_accounts; @accounts.keys; end
  def user_emails; (@email_map.keys + @alternate_map.keys).uniq.select { |e| String === e }; end

  def add_account hash, default=false
    email = hash[:email]

    next if @email_map.member? email
    a = Account.new hash
    @accounts[a] = true
    @email_map[email] = a
    hash[:alternates].each { |aa| @alternate_map[aa] = a }
    if default
      raise ArgumentError, "multiple default accounts" if @default_account
      @default_account = a 
    end
  end

  def is_account? p; @accounts.member? p; end
  def account_for email
    @email_map[email] || @alternate_map[email] || @alternate_map.argfind { |k, v| k === email && v }
  end
  def is_account_email? email; !account_for(email).nil?; end
end

end
