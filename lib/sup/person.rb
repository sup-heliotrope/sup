module Redwood

class PersonManager
  include Singleton

  def initialize fn
    @fn = fn
    @names = {}
    IO.readlines(fn).map { |l| l =~ /^(.*)?:\s+(\d+)\s+(.*)$/ && @names[$1] = [$2.to_i, $3] } if File.exists? fn
    self.class.i_am_the_instance self
  end

  def name_for email; @names.member?(email) ? @names[email][1] : nil; end
  def register email, name
    return unless name

    name = name.gsub(/^\s+|\s+$/, "").gsub(/\s+/, " ").gsub(/^['"]|['"]$/, "")

    ## all else being equal, prefer longer names, unless the prior name
    ## doesn't contain any capitalization
    oldcount, oldname = @names[email]
    @names[email] = [0, name] if oldname.nil? || oldname.length < name.length || (oldname !~ /[A-Z]/ && name =~ /[A-Z]/)
    @names[email][0] = Time.now.to_i
  end

  def save; File.open(@fn, "w") { |f| @names.each { |email, (time, name)| f.puts "#{email}: #{time} #{name}" unless email =~ /no\-?reply/ } }; end
end

class Person
  @@email_map = {}

  attr_accessor :name, :email

  def initialize name, email
    raise ArgumentError, "email can't be nil" unless email
    @email = email.gsub(/^\s+|\s+$/, "").gsub(/\s+/, " ").downcase
    PersonManager.register @email, name
    @name = PersonManager.name_for @email
  end

  def == o; o && o.email == email; end
  alias :eql? :==
  def hash; [name, email].hash; end

  def shortname
    case @name
    when /\S+, (\S+)/
      $1
    when /(\S+) \S+/
      $1
    when nil
      @email
    else
      @name
    end
  end

  def longname
    if @name && @email
      "#@name <#@email>"
    else
      @email
    end
  end

  def mediumname; @name || @email; end

  def full_address
    if @name && @email
      if @name =~ /"/
        "#{@name.inspect} <#@email>" # escape quotes
      else
        "#@name <#@email>"
      end
    else
      @email
    end
  end

  ## when sorting addresses, sort by this 
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

  def self.for s
    return nil if s.nil?

    ## try and parse an email address and name
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

    @@email_map[email] ||= Person.new name, email
  end

  def self.for_several s
    return [] if s.nil?

    s.split_on_commas.map { |ss| self.for ss }
  end
end

end
