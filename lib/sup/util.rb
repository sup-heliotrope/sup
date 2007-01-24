class Module
  def bool_reader *args
    args.each { |sym| class_eval %{ def #{sym}?; @#{sym}; end } }
  end
  def bool_writer *args; attr_writer(*args); end
  def bool_accessor *args
    bool_reader(*args)
    bool_writer(*args)
  end

  def attr_reader_cloned *args
    args.each { |sym| class_eval %{ def #{sym}; @#{sym}.clone; end } }
  end

  def defer_all_other_method_calls_to obj
    class_eval %{ def method_missing meth, *a, &b; @#{obj}.send meth, *a, &b; end }
  end
end

class Object
  def ancestors
    ret = []
    klass = self.class

    until klass == Object
      ret << klass
      klass = klass.superclass
    end
    ret
  end

  ## takes a value which it yields and then returns, so that code
  ## like:
  ##
  ## x = expensive_operation
  ## log "got #{x}"
  ## x
  ##
  ## now becomes:
  ##
  ## with(expensive_operation) { |x| log "got #{x}" }
  ##
  ## i'm sure there's pithy comment i could make here about the
  ## superiority of lisp, but fuck lisp.
  def returning x; yield x; x; end

  ## clone of java-style whole-method synchronization
  ## assumes a @mutex variable
  def synchronized *meth
    meth.each do
      class_eval <<-EOF
        alias unsynchronized_#{meth} #{meth}
        def #{meth}(*a, &b)
          @mutex.synchronize { unsynchronized_#{meth}(*a, &b) }
        end
      EOF
    end
  end
end

class String
  def camel_to_hyphy
    self.gsub(/([a-z])([A-Z0-9])/, '\1-\2').downcase
  end

  def find_all_positions x
    ret = []
    start = 0
    while start < length
      pos = index x, start
      break if pos.nil?
      ret << pos
      start = pos + 1
    end
    ret
  end

  def ucfirst
    self[0 .. 0].upcase + self[1 .. -1]
  end

  ## a very complicated regex found on teh internets to split on
  ## commas, unless they occurr within double quotes.
  def split_on_commas
    split(/,\s*(?=(?:[^"]*"[^"]*")*(?![^"]*"))/)
  end

  def wrap len
    ret = []
    s = self
    while s.length > len
      cut = s[0 ... len].rindex(/\s/)
      if cut
        ret << s[0 ... cut]
        s = s[(cut + 1) .. -1]
      else
        ret << s[0 ... len]
        s = s[len .. -1]
      end
    end
    ret << s
  end

  def normalize_whitespace
    gsub(/\t/, "    ").gsub(/\r/, "")
  end
end

class Numeric
  def clamp min, max
    if self < min
      min
    elsif self > max
      max
    else
      self
    end
  end

  def in? range; range.member? self; end
end

class Fixnum
  def num_digits base=10
    return 1 if self == 0
    1 + (Math.log(self) / Math.log(10)).floor
  end
  
  def to_character
    if self < 128 && self >= 0
      chr
    else
      "<#{self}>"
    end
  end
end

class Hash
  def - o
    Hash[*self.map { |k, v| [k, v] unless o.include? k }.compact.flatten_one_level]
  end

  def select_by_value v=true
    select { |k, vv| vv == v }.map { |x| x.first }
  end
end

module Enumerable
  def map_with_index
    ret = []
    each_with_index { |x, i| ret << yield(x, i) }
    ret
  end

  def sum; inject(0) { |x, y| x + y }; end
  
  def map_to_hash
    ret = {}
    each { |x| ret[x] = yield(x) }
    ret
  end

  # like find, except returns the value of the block rather than the
  # element itself.
  def argfind
    ret = nil
    find { |e| ret ||= yield(e) }
    ret || nil # force
  end

  def argmin
    best, bestval = nil, nil
    each do |e|
      val = yield e
      if bestval.nil? || val < bestval
        best, bestval = e, val
      end
    end
    best
  end
end

class Array
  def flatten_one_level
    inject([]) { |a, e| a + e }
  end

  def to_h; Hash[*flatten]; end
  def rest; self[1..-1]; end

  def to_boolean_h; Hash[*map { |x| [x, true] }.flatten]; end
end

class Time
  def to_indexable_s
    sprintf "%012d", self
  end

  def nearest_hour
    if min < 30
      self
    else
      self + (60 - min) * 60
    end
  end

  def midnight # within a second
    self - (hour * 60 * 60) - (min * 60) - sec
  end

  def is_the_same_day? other
    (midnight - other.midnight).abs < 1
  end

  def is_the_day_before? other
    other.midnight - midnight <=  24 * 60 * 60 + 1
  end

  def to_nice_distance_s from=Time.now
    later_than = (self < from)
    diff = (self.to_i - from.to_i).abs.to_f
    text = 
      [ ["second", 60],
        ["minute", 60],
        ["hour", 24],
        ["day", 7],
        ["week", 4.345], # heh heh
        ["month", 12],
        ["year", nil],
      ].argfind do |unit, size|
        if diff.round <= 1
          "one #{unit}"
        elsif size.nil? || diff.round < size
          "#{diff.round} #{unit}s"
        else
          diff /= size.to_f
          false
        end
      end
    if later_than
      text + " ago"
    else
      "in " + text
    end  
  end

  TO_NICE_S_MAX_LEN = 9 # e.g. "Yest.10am"
  def to_nice_s from=Time.now
    if year != from.year
      strftime "%b %Y"
    elsif month != from.month
      strftime "%b %e"
    else
      if is_the_same_day? from
        strftime("%l:%M%P")
      elsif is_the_day_before? from
        "Yest."  + nearest_hour.strftime("%l%P")
      else
        strftime "%b %e"
      end
    end
  end
end

## simple singleton module. far less complete and insane than the ruby
## standard library one, but automatically forwards methods calls and
## allows for constructors that take arguments.
##
## You must have #initialize call "self.class.i_am_the_instance self"
## at some point or everything will fail horribly
module Singleton
  module ClassMethods
    def instance; @instance; end
    def instantiated?; defined?(@instance) && !@instance.nil?; end
    def method_missing meth, *a, &b
      raise "no instance defined!" unless defined? @instance
      @instance.send meth, *a, &b
    end
    def i_am_the_instance o
      raise "there can be only one! (instance)" if defined? @instance
      @instance = o
    end
  end

  def self.included klass
    klass.extend ClassMethods
  end
end
