module Redwood

class PersonManager
  include Singleton

  def initialize
    self.class.i_am_the_instance self
  end

  def self.people_for s
    return [] if s.nil?
    s.split_on_commas.map { |ss| self.person_for ss }
  end

  def self.person_for s
    Person.from_address(s)
  end
end

class Person 
  attr_accessor :name, :email

  def initialize name, email
    raise ArgumentError, "email can't be nil" unless email
    
    if name
      @name = name.gsub(/^\s+|\s+$/, "").gsub(/\s+/, " ")
      if @name =~ /^(['"]\s*)(.*?)(\s*["'])$/
        @name = $2
      end
    end

    @email = email.gsub(/^\s+|\s+$/, "").gsub(/\s+/, " ").downcase
  end

  def to_s; "#@name <#@email>" end

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

  def indexable_content
    [name, email, email.split(/@/).first].join(" ")
  end

  def eql? o; email.eql? o.email end
  def hash; email.hash end
end

end
