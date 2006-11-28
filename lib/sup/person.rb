module Redwood

class Person
  @@email_map = {}

  attr_accessor :name, :email

  def initialize name, email
    raise ArgumentError, "email can't be nil" unless email
    @name = 
      if name
        name.gsub(/^\s+|\s+$/, "").gsub(/\s+/, " ")
      else
        nil
      end
    @email = email.gsub(/^\s+|\s+$/, "").gsub(/\s+/, " ").downcase
    @@email_map[@email] = self
  end

  def == o; o && o.email == email; end
  alias :eql? :==

  def hash
    [name, email].hash
  end

  def shortname
    case @name
    when /\S+, (\S+)/
      $1
    when /(\S+) \S+/
      $1
    when nil
      @email #[0 ... 10]
    else
      @name #[0 ... 10]
    end
  end

  def longname
    if @name && @email
      "#@name <#@email>"
    else
      @email
    end
  end

  def mediumname
    if @name
      name
    else
      @email
    end
  end

  def full_address
    if @name && @email
      if @name =~ /"/
        "#{@name.inspect} <#@email>"
      else
        "#@name <#@email>"
      end
    else
      @email
    end
  end

  def sort_by_me
    case @name
    when /^(\S+), \S+/
      $1
    when /^\S+ \S+ (\S+)/
      $1
    when /^\S+ (\S+)/
      $1
    when nil
      @email
    else
      @name
    end.downcase
  end

  def self.for_several s
    return [] if s.nil?

    begin
      s.split_on_commas.map { |ss| self.for ss }
    rescue StandardError => e
      raise "#{e.message}: for #{s.inspect}"
    end
  end

  def self.for s
    return nil if s.nil?
    name, email =
      case s
      when /["'](.*?)["'] <(.*?)>/, /([^,]+) <(.*?)>/
        a, b = $1, $2
        [a.gsub('\"', '"'), b]
      when /<((\S+?)@\S+?)>/
        [$2, $1]
      when /((\S+?)@\S+)/
        [$2, $1]
      else
        [nil, s]
      end

    if name && (p = @@email_map[email])
      ## all else being equal, prefer longer names, unless the prior name
      ## doesn't contain any capitalization
      p.name = name if (p.name.nil? || p.name.length < name.length) unless
        p.name =~ /[A-Z]/ || (AccountManager.instantiated? && AccountManager.is_account?(p))
      p 
    else
      Person.new name, email
    end
  end
end

end
