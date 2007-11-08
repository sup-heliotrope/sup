require 'lockfile'
require 'mime/types'
require 'pathname'

## time for some monkeypatching!
class Lockfile
  def gen_lock_id
    Hash[
         'host' => "#{ Socket.gethostname }",
         'pid' => "#{ Process.pid }",
         'ppid' => "#{ Process.ppid }",
         'time' => timestamp,
         'pname' => $0,
         'user' => ENV["USER"]
        ]
  end

  def dump_lock_id lock_id = @lock_id
      "host: %s\npid: %s\nppid: %s\ntime: %s\nuser: %s\npname: %s\n" %
        lock_id.values_at('host','pid','ppid','time','user', 'pname')
    end

  def lockinfo_on_disk
    h = load_lock_id IO.read(path)
    h['mtime'] = File.mtime path
    h
  end

  def touch_yourself; touch path end
end

class Pathname
  def human_size
    s =
      begin
        size
      rescue SystemCallError
        return "?"
      end

    if s < 1024
      s.to_s + "b"
    elsif s < (1024 * 1024)
      (s / 1024).to_s + "k"
    elsif s < (1024 * 1024 * 1024)
      (s / 1024 / 1024).to_s + "m"
    else
      (s / 1024 / 1024 / 1024).to_s + "g"
    end
  end

  def human_time
    begin
      ctime.strftime("%Y-%m-%d %H:%M")
    rescue SystemCallError
      "?"
    end
  end
end

## more monkeypatching!
module RMail
  class EncodingUnsupportedError < StandardError; end

  class Message
    def add_file_attachment fn
      bfn = File.basename fn
      a = Message.new
      t = MIME::Types.type_for(bfn).first || MIME::Types.type_for("exe").first

      a.header.add "Content-Disposition", "attachment; filename=#{bfn.to_s.inspect}"
      a.header.add "Content-Type", "#{t.content_type}; name=#{bfn.to_s.inspect}"
      a.header.add "Content-Transfer-Encoding", t.encoding
      a.body =
        case t.encoding
        when "base64"
          [IO.read(fn)].pack "m"
        when "quoted-printable"
          [IO.read(fn)].pack "M"
        when "7bit", "8bit"
          IO.read(fn)
        else
          raise EncodingUnsupportedError, t.encoding
        end

      add_part a
    end

    def charset
      if header.field?("content-type") && header.fetch("content-type") =~ /charset="?(.*?)"?(;|$)/
        $1
      end
    end
  end
end

class Range
  ## only valid for integer ranges (unless I guess it's exclusive)
  def size 
    last - first + (exclude_end? ? 0 : 1)
  end
end

class Module
  def bool_reader *args
    args.each { |sym| class_eval %{ def #{sym}?; @#{sym}; end } }
  end
  def bool_writer *args; attr_writer(*args); end
  def bool_accessor *args
    bool_reader(*args)
    bool_writer(*args)
  end

  def defer_all_other_method_calls_to obj
    class_eval %{
      def method_missing meth, *a, &b; @#{obj}.send meth, *a, &b; end
      def respond_to? meth; @#{obj}.respond_to?(meth); end
    }
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

  ## "k combinator"
  def returning x; yield x; x; end

  ## clone of java-style whole-method synchronization
  ## assumes a @mutex variable
  ## TODO: clean up, try harder to avoid namespace collisions
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

  def ignore_concurrent_calls *meth
    meth.each do
      mutex = "@__concurrent_protector_#{meth}"
      flag = "@__concurrent_flag_#{meth}"
      oldmeth = "__unprotected_#{meth}"
      class_eval <<-EOF
        alias #{oldmeth} #{meth}
        def #{meth}(*a, &b)
          #{mutex} = Mutex.new unless defined? #{mutex}
          #{flag} = true unless defined? #{flag}
          run = #{mutex}.synchronize do
            if #{flag}
              #{flag} = false
              true
            end
          end
          if run
            ret = #{oldmeth}(*a, &b)
            #{mutex}.synchronize { #{flag} = true }
            ret
          end
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

  ## one of the few things i miss from perl
  def ucfirst
    self[0 .. 0].upcase + self[1 .. -1]
  end

  ## a very complicated regex found on teh internets to split on
  ## commas, unless they occurr within double quotes.
  def split_on_commas
    split(/,\s*(?=(?:[^"]*"[^"]*")*(?![^"]*"))/)
  end

  ## ok, here we do it the hard way. got to have a remainder for purposes of
  ## tab-completing full email addresses
  def split_on_commas_with_remainder
    ret = []
    state = :outstring
    pos = 0
    region_start = 0
    while pos <= length
      newpos = case state
        when :escaped_instring, :escaped_outstring: pos
        else index(/[,"\\]/, pos)
      end 
      
      if newpos
        char = self[newpos]
      else
        char = nil
        newpos = length
      end
        
      $stderr.puts "pos #{newpos} (len #{length}), state #{state}, char #{(char || ?$).chr}, region_start #{region_start}"
      case char
      when ?"
        state = case state
          when :outstring: :instring
          when :instring: :outstring
          when :escaped_instring: :instring
          when :escaped_outstring: :outstring
        end
      when ?,, nil
        state = case state
          when :outstring, :escaped_outstring:
            ret << self[region_start ... newpos]
            region_start = newpos + 1
            :outstring
          when :instring: :instring
          when :escaped_instring: :instring
        end
      when ?\\
        state = case state
          when :instring: :escaped_instring
          when :outstring: :escaped_outstring
          when :escaped_instring: :instring
          when :escaped_outstring: :outstring
        end
      end
      pos = newpos + 1
    end

    remainder = case state
      when :instring
        self[region_start .. -1]
      else
        nil
      end

    [ret, remainder]
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

  def pluralize s
    to_s + " " + (self == 1 ? s : s + "s")
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

  ## returns the maximum shared prefix of an array of strings
  ## optinally excluding a prefix
  def shared_prefix caseless=false, exclude=""
    return "" if empty?
    prefix = ""
    (0 ... first.length).each do |i|
      c = (caseless ? first.downcase : first)[i]
      break unless all? { |s| (caseless ? s.downcase : s)[i] == c }
      next if exclude[i] == c
      prefix += first[i].chr
    end
    prefix
  end

  def max_of
    map { |e| yield e }.max
  end
end

class Array
  def flatten_one_level
    inject([]) { |a, e| a + e }
  end

  def to_h; Hash[*flatten]; end
  def rest; self[1..-1]; end

  def to_boolean_h; Hash[*map { |x| [x, true] }.flatten]; end

  def last= e; self[-1] = e end
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
## at some point or everything will fail horribly.
module Singleton
  module ClassMethods
    def instance; @instance; end
    def instantiated?; defined?(@instance) && !@instance.nil?; end
    def deinstantiate!; @instance = nil; end
    def method_missing meth, *a, &b
      raise "no instance defined!" unless defined? @instance

      ## if we've been deinstantiated, just drop all calls. this is
      ## useful because threads that might be active during the
      ## cleanup process (e.g. polling) would otherwise have to
      ## special-case every call to a Singleton object
      return nil if @instance.nil?

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

## wraps an object. if it throws an exception, keeps a copy, and
## rethrows it for any further method calls.
class Recoverable
  def initialize o
    @o = o
    @e = nil
  end

  def clear_error!; @e = nil; end
  def has_errors?; !@e.nil?; end
  def error; @e; end

  def method_missing m, *a, &b; __pass m, *a, &b; end
  
  def id; __pass :id; end
  def to_s; __pass :to_s; end
  def to_yaml x; __pass :to_yaml, x; end
  def is_a? c; @o.is_a? c; end

  def respond_to? m; @o.respond_to? m end

  def __pass m, *a, &b
    begin
      @o.send(m, *a, &b)
    rescue Exception => e
      @e = e
      raise e
    end
  end
end

## acts like a hash with an initialization block, but saves any
## newly-created value even upon lookup.
##
## for example:
##
## class C
##   attr_accessor :val
##   def initialize; @val = 0 end
## end
## 
## h = Hash.new { C.new }
## h[:a].val # => 0
## h[:a].val = 1
## h[:a].val # => 0
##
## h2 = SavingHash.new { C.new }
## h2[:a].val # => 0
## h2[:a].val = 1
## h2[:a].val # => 1
##
## important note: you REALLY want to use #member? to test existence,
## because just checking h[anything] will always evaluate to true
## (except for degenerate constructor blocks that return nil or false)
class SavingHash
  def initialize &b
    @constructor = b
    @hash = Hash.new
  end

  def [] k
    @hash[k] ||= @constructor.call(k)
  end

  defer_all_other_method_calls_to :hash
end
