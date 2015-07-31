# encoding: utf-8

require 'thread'
require 'lockfile'
require 'mime/types'
require 'pathname'
require 'set'
require 'enumerator'
require 'benchmark'
require 'unicode'
require 'fileutils'

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
    h['path'] = path
    h
  end

  def touch_yourself; touch path end
end

class File
  # platform safe file.link which attempts a copy if hard-linking fails
  def self.safe_link src, dest
    begin
      File.link src, dest
    rescue
      FileUtils.copy src, dest
    end
  end
end

class Pathname
  def human_size
    s =
      begin
        size
      rescue SystemCallError
        return "?"
      end
    s.to_human_size
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
    def self.make_file_attachment fn
      bfn = File.basename fn
      t = MIME::Types.type_for(bfn).first || MIME::Types.type_for("exe").first
      make_attachment IO.read(fn), t.content_type, t.encoding, bfn.to_s
    end

    def charset
      if header.field?("content-type") && header.fetch("content-type") =~ /charset\s*=\s*"?(.*?)"?(;|$)/i
        $1
      end
    end

    def self.make_attachment payload, mime_type, encoding, filename
      a = Message.new
      a.header.add "Content-Disposition", "attachment; filename=#{filename.inspect}"
      a.header.add "Content-Type", "#{mime_type}; name=#{filename.inspect}"
      a.header.add "Content-Transfer-Encoding", encoding if encoding
      a.body =
        case encoding
        when "base64"
          [payload].pack "m"
        when "quoted-printable"
          [payload].pack "M"
        when "7bit", "8bit", nil
          payload
        else
          raise EncodingUnsupportedError, encoding.inspect
        end
      a
    end
  end

  class Serialize
    ## Don't add MIME-Version headers on serialization. Sup sometimes want's to serialize
    ## message parts where these headers are not needed and messing with the message on
    ## serialization breaks gpg signatures. The commented section shows the original RMail
    ## code.
    def calculate_boundaries(message)
      calculate_boundaries_low(message, [])
      # unless message.header['MIME-Version']
      #   message.header['MIME-Version'] = "1.0"
      # end
    end
  end

  class Header

    # Convert to ASCII before trying to match with regexp
    class Field

      class << self
        def parse(field)
          field = field.dup.to_s
          field = field.fix_encoding!.ascii
          if field =~ EXTRACT_FIELD_NAME_RE
            [ $1, $'.chomp ]
          else
            [ "", Field.value_strip(field) ]
          end
        end
      end
    end

    ## Be more cautious about invalid content-type headers
    ## the original RMail code calls
    ## value.strip.split(/\s*;\s*/)[0].downcase
    ## without checking if split returned an element

    # This returns the full content type of this message converted to
    # lower case.
    #
    # If there is no content type header, returns the passed block is
    # executed and its return value is returned.  If no block is passed,
    # the value of the +default+ argument is returned.
    def content_type(default = nil)
      if value = self['content-type'] and ct = value.strip.split(/\s*;\s*/)[0]
        return ct.downcase
      else
        if block_given?
          yield
        else
          default
        end
      end
    end
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
      def respond_to?(m, include_private = false)
        @#{obj}.respond_to?(m, include_private)
      end
    }
  end
end

class Object
  ## "k combinator"
  def returning x; yield x; x; end

  unless method_defined? :tap
    def tap; yield self; self; end
  end

  ## clone of java-style whole-method synchronization
  ## assumes a @mutex variable
  ## TODO: clean up, try harder to avoid namespace collisions
  def synchronized *methods
    methods.each do |meth|
      class_eval <<-EOF
        alias unsynchronized_#{meth} #{meth}
        def #{meth}(*a, &b)
          @mutex.synchronize { unsynchronized_#{meth}(*a, &b) }
        end
      EOF
    end
  end

  def ignore_concurrent_calls *methods
    methods.each do |meth|
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

  def benchmark s, &b
    ret = nil
    times = Benchmark.measure { ret = b.call }
    debug "benchmark #{s}: #{times}"
    ret
  end
end

class String
  def display_length
    @display_length ||= Unicode.width(self.fix_encoding!, false)

    # if Unicode.width fails and returns -1, fall back to
    # regular String#length, see pull-request: #256.
    if @display_length < 0
      @display_length = self.length
    end

    @display_length
  end

  def slice_by_display_length len
    each_char.each_with_object "" do |c, buffer|
      width = Unicode.width(c, false)
      width = 1 if width < 0
      len -= width
      return buffer if len < 0
      buffer << c
    end
  end

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

  ## a very complicated regex found on teh internets to split on
  ## commas, unless they occurr within double quotes.
  def split_on_commas
    normalize_whitespace().split(/,\s*(?=(?:[^"]*"[^"]*")*(?![^"]*"))/)
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
        when :escaped_instring, :escaped_outstring then pos
        else index(/[,"\\]/, pos)
      end

      if newpos
        char = self[newpos]
      else
        char = nil
        newpos = length
      end

      case char
      when ?"
        state = case state
          when :outstring then :instring
          when :instring then :outstring
          when :escaped_instring then :instring
          when :escaped_outstring then :outstring
        end
      when ?,, nil
        state = case state
          when :outstring, :escaped_outstring then
            ret << self[region_start ... newpos].gsub(/^\s+|\s+$/, "")
            region_start = newpos + 1
            :outstring
          when :instring then :instring
          when :escaped_instring then :instring
        end
      when ?\\
        state = case state
          when :instring then :escaped_instring
          when :outstring then :escaped_outstring
          when :escaped_instring then :instring
          when :escaped_outstring then :outstring
        end
      end
      pos = newpos + 1
    end

    remainder = case state
      when :instring
        self[region_start .. -1].gsub(/^\s+/, "")
      else
        nil
      end

    [ret, remainder]
  end

  def wrap len
    ret = []
    s = self
    while s.display_length > len
      slice = s.slice_by_display_length(len)
      cut = slice.rindex(/\s/)
      if cut
        ret << s[0 ... cut]
        s = s[(cut + 1) .. -1]
      else
        ret << slice
        s = s[slice.length .. -1]
      end
    end
    ret << s
  end

  # Fix the damn string! make sure it is valid utf-8, then convert to
  # user encoding.
  def fix_encoding!
    # first try to encode to utf-8 from whatever current encoding
    encode!('UTF-8', :invalid => :replace, :undef => :replace)

    # do this anyway in case string is set to be UTF-8, encoding to
    # something else (UTF-16 which can fully represent UTF-8) and back
    # ensures invalid chars are replaced.
    encode!('UTF-16', 'UTF-8', :invalid => :replace, :undef => :replace)
    encode!('UTF-8', 'UTF-16', :invalid => :replace, :undef => :replace)

    fail "Could not create valid UTF-8 string out of: '#{self.to_s}'." unless valid_encoding?

    # now convert to $encoding
    encode!($encoding, :invalid => :replace, :undef => :replace)

    fail "Could not create valid #{$encoding.inspect} string out of: '#{self.to_s}'." unless valid_encoding?

    self
  end

  # transcode the string if original encoding is know
  # fix if broken.
  def transcode to_encoding, from_encoding
    begin
      encode!(to_encoding, from_encoding, :invalid => :replace, :undef => :replace)

      unless valid_encoding?
        # fix encoding (through UTF-8)
        encode!('UTF-16', from_encoding, :invalid => :replace, :undef => :replace)
        encode!(to_encoding, 'UTF-16', :invalid => :replace, :undef => :replace)
      end

    rescue Encoding::ConverterNotFoundError
      debug "Encoding converter not found for #{from_encoding.inspect} or #{to_encoding.inspect}, fixing string: '#{self.to_s}', but expect weird characters."
      fix_encoding!
    end

    fail "Could not create valid #{to_encoding.inspect} string out of: '#{self.to_s}'." unless valid_encoding?

    self
  end

  def normalize_whitespace
    fix_encoding!
    gsub(/\t/, "    ").gsub(/\r/, "")
  end

  unless method_defined? :ord
    def ord
      self[0]
    end
  end

  unless method_defined? :each
    def each &b
      each_line &b
    end
  end

  ## takes a list of words, and returns an array of symbols.  typically used in
  ## Sup for translating Xapian's representation of a list of labels (a string)
  ## to an array of label symbols.
  ##
  ## split_on will be passed to String#split, so you can leave this nil for space.
  def to_set_of_symbols split_on=nil; Set.new split(split_on).map { |x| x.strip.intern } end

  class CheckError < ArgumentError; end
  def check
    begin
      fail "unexpected encoding #{encoding}" if respond_to?(:encoding) && !(encoding == Encoding::UTF_8 || encoding == Encoding::ASCII)
      fail "invalid encoding" if respond_to?(:valid_encoding?) && !valid_encoding?
    rescue
      raise CheckError.new($!.message)
    end
  end

  def ascii
    out = ""
    each_byte do |b|
      if (b & 128) != 0
        out << "\\x#{b.to_s 16}"
      else
        out << b.chr
      end
    end
    out = out.fix_encoding! # this should now be an utf-8 string of ascii
                           # compat chars.
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

  def to_human_size
    if self < 1024
      to_s + "B"
    elsif self < (1024 * 1024)
      (self / 1024).to_s + "KiB"
    elsif self < (1024 * 1024 * 1024)
      (self / 1024 / 1024).to_s + "MiB"
    else
      (self / 1024 / 1024 / 1024).to_s + "GiB"
    end
  end
end

class Fixnum
  def to_character
    if self < 128 && self >= 0
      chr
    else
      "<#{self}>"
    end
  end

  ## hacking the english language
  def pluralize s
    to_s + " " +
      if self == 1
        s
      else
        if s =~ /(.*)y$/
          $1 + "ies"
        else
          s + "s"
        end
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

  ## returns all the entries which are equal to startline up to endline
  def between startline, endline
    select { |l| true if l == startline .. l == endline }
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
  def nonempty?; !empty? end
end

## simple singleton module. far less complete and insane than the ruby standard
## library one, but it automatically forwards methods calls and allows for
## constructors that take arguments.
##
## classes that inherit this can define initialize. however, you cannot call
## .new on the class. To get the instance of the class, call .instance;
## to create the instance, call init.
module Redwood
  module Singleton
    module ClassMethods
      def instance; @instance; end
      def instantiated?; defined?(@instance) && !@instance.nil?; end
      def deinstantiate!; @instance = nil; end
      def method_missing meth, *a, &b
        raise "no #{name} instance defined in method call to #{meth}!" unless defined? @instance

        ## if we've been deinstantiated, just drop all calls. this is
        ## useful because threads that might be active during the
        ## cleanup process (e.g. polling) would otherwise have to
        ## special-case every call to a Singleton object
        return nil if @instance.nil?

        # Speed up further calls by defining a shortcut around method_missing
        if meth.to_s[-1,1] == '='
          # Argh! Inconsistency! Setters do not work like all the other methods.
          class_eval "def self.#{meth}(a); @instance.send :#{meth}, a; end"
        else
          class_eval "def self.#{meth}(*a, &b); @instance.send :#{meth}, *a, &b; end"
        end

        @instance.send meth, *a, &b
      end
      def init *args
        raise "there can be only one! (instance)" if instantiated?
        @instance = new(*args)
      end
    end

    def self.included klass
      klass.private_class_method :allocate, :new
      klass.extend ClassMethods
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

## easy thread-safe class for determining who's the "winner" in a race (i.e.
## first person to hit the finish line
class FinishLine
  def initialize
    @m = Mutex.new
    @over = false
  end

  def winner?
    @m.synchronize { !@over && @over = true }
  end
end

