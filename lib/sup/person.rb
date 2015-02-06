module Redwood

class Person
  attr_accessor :name, :email

  def initialize name, email
    raise ArgumentError, "email can't be nil" unless email

    email.fix_encoding!

    @name = if name
      name.fix_encoding!
      name = name.strip.gsub(/\s+/, " ")
      name =~ /^(['"]\s*)(.*?)(\s*["'])$/ ? $2 : name
      name.gsub('\\\\', '\\')
    end

    @email = email.strip.gsub(/\s+/, " ")
  end

  def to_s
    if @name
      "#@name <#@email>"
    else
      @email
    end
  end

#   def == o; o && o.email == email; end
#   alias :eql? :==

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

  def mediumname; @name || @email; end

  def longname
    to_s
  end

  def full_address
    Person.full_address @name, @email
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

  def eql? o; email.eql? o.email end
  def hash; email.hash end


  ## see comments in self.from_address
  def indexable_content
    [name, email, email.split(/@/).first].join(" ")
  end

  class << self

    def full_address name, email
      if name && email
        if name =~ /[",@]/
          "#{name.inspect} <#{email}>" # escape quotes
        else
          "#{name} <#{email}>"
        end
      else
        email
      end
    end

    ## return "canonical" person using contact manager or create one if
    ## not found or contact manager not available
    def from_name_and_email name, email
      ContactManager.instantiated? && ContactManager.person_for(email) || Person.new(name, email)
    end

    def from_address s
      return nil if s.nil?

      ## try and parse an email address and name
      name, email = case s
        when /(.+?) ((\S+?)@\S+) \3/
          ## ok, this first match cause is insane, but bear with me.  email
          ## addresses are stored in the to/from/etc fields of the index in a
          ## weird format: "name address first-part-of-address", i.e.  spaces
          ## separating those three bits, and no <>'s. this is the output of
          ## #indexable_content. here, we reverse-engineer that format to extract
          ## a valid address.
          ##
          ## we store things this way to allow searches on a to/from/etc field to
          ## match any of those parts. a more robust solution would be to store a
          ## separate, non-indexed field with the proper headers. but this way we
          ## save precious bits, and it's backwards-compatible with older indexes.
          [$1, $2]
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

      from_name_and_email name, email
    end

    def from_address_list ss
      return [] if ss.nil?
      ss.dup.split_on_commas.map { |s| self.from_address s }
    end

  end

end

end
