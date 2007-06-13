module Redwood

class Account < Person
  attr_accessor :sendmail, :signature

  def initialize email, h
    super h[:name], email, 0, true
    @sendmail = h[:sendmail]
    @signature = h[:signature]
  end
end

class AccountManager
  include Singleton

  attr_accessor :default_account

  def initialize accounts
    @email_map = {}
    @accounts = {}
    @default_account = nil

    add_account accounts[:default], true
    accounts.each { |k, v| add_account v unless k == :default }

    self.class.i_am_the_instance self
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

    main_email = hash[:email]
    ([hash[:email]] + hash[:alternates]).each do |email|
      next if @email_map.member? email
      a = Account.new main_email, hash
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
