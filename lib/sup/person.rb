module Redwood

class PersonManager
  include Singleton

  def initialize fn
    @fn = fn
    @@people = {}

    ## read in stored people
    IO.readlines(fn).map do |l|
      l =~ /^(.*)?:\s+(\d+)\s+(.*)$/ or raise "can't parse: #{l}"
      email, time, name = $1, $2, $3
      @@people[email] = Person.new name, email, time, false
    end if File.exists? fn

    self.class.i_am_the_instance self
  end

  def save
    File.open(@fn, "w") do |f|
      @@people.each do |email, p|
        next if p.email == p.name
        next if p.email =~ /=/ # drop rfc2047-encoded, and lots of other useless emails. definitely a heuristic.
        f.puts "#{p.email}: #{p.timestamp} #{p.name}"
      end
    end
  end

  def self.people_for s, opts={}
    return [] if s.nil?
    s.split_on_commas.map { |ss| self.person_for ss, opts }
  end

  def self.person_for s, opts={}
    p = Person.from_address(s) or return nil
    p.definitive = true if opts[:definitive]
    register p
  end
  
  def self.register p
    oldp = @@people[p.email]

    if oldp.nil? || p.better_than?(oldp)
      @@people[p.email] = p
    end

    @@people[p.email].touch!
    @@people[p.email]
  end
end

## don't create these by hand. rather, go through personmanager, to
## ensure uniqueness and overriding.
class Person 
  attr_accessor :name, :email, :timestamp
  bool_accessor :definitive

  def initialize name, email, timestamp=0, definitive=false
    raise ArgumentError, "email can't be nil" unless email
    
    if name
      @name = name.gsub(/^\s+|\s+$/, "").gsub(/\s+/, " ")
      if @name =~ /^(['"]\s*)(.*?)(\s*["'])$/
        @name = $2
      end
    end

    @email = email.gsub(/^\s+|\s+$/, "").gsub(/\s+/, " ").downcase
    @definitive = definitive
    @timestamp = timestamp
  end

  ## heuristic: whether the name attached to this email is "real", i.e. 
  ## we should bother to store it.
  def generic?
    @email =~ /no\-?reply/
  end

  def better_than? o
    return false if o.definitive? || generic?
    return true if definitive?
    o.name.nil? || (name && name.length > o.name.length && name =~ /[a-z]/)
  end

  def to_s; "#@name <#@email>" end

  def touch!; @timestamp = Time.now.to_i end

#   def == o; o && o.email == email; end
#   alias :eql? :==
#   def hash; [name, email].hash; end

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
      if @name =~ /[",@]/
        "#{@name.inspect} <#{@email}>" # escape quotes
      else
        "#{@name} <#{@email}>"
      end
    else
      email
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

  def self.from_address s
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

    Person.new name, email
  end

  def eql? o; email.eql? o.email end
  def hash; email.hash end
end

end
