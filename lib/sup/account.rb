module Redwood

class Account < Person
  attr_accessor :sendmail, :sig_file

  def initialize email, h
    super h[:name], email, 0, true
    @sendmail = h[:sendmail]
    @sig_file = h[:signature]
  end
end

class AccountManager
  include Singleton

  attr_accessor :default_account

  def initialize accounts
    @email_map = {}
    @accounts = {}
    @default_account = nil

    accounts.each { |k, v| add_account v, k == :default }

    self.class.i_am_the_instance self
  end

  def user_accounts; @accounts.keys; end
  def user_emails; @email_map.keys.select { |e| String === e }; end

  def add_account hash, default=false
    main_email = hash[:email]

    ([hash[:email]] + (hash[:alternates] || [])).each do |email|
      next if @email_map.member? email
      a = Account.new email, hash
      PersonManager.register a
      @accounts[a] = true
      @email_map[email] = a
    end

    if default
      raise ArgumentError, "multiple default accounts" if @default_account
      @default_account = @email_map[main_email]
    end
  end

  def is_account? p; is_account_email? p.email end
  def account_for email; @email_map[email] end
  def is_account_email? email; !account_for(email).nil? end
end

end
