module Redwood

class Logger
  @@instance = nil

  attr_reader :buf

  def initialize
    raise "only one Log can be defined" if @@instance
    @@instance = self
    @mode = LogMode.new
    @respawn = true
    @spawning = false # to prevent infinite loops!
  end

  ## must be called if you want to see anything!
  ## once called, will respawn if killed...
  def make_buf
    return if @mode.buffer || !BufferManager.instantiated? || !@respawn || @spawning
    @spawning = true
    @mode.buffer = BufferManager.instance.spawn "log", @mode, :hidden => true, :system => true
    @spawning = false
  end

  def log s
#    $stderr.puts s
    make_buf
    prefix = "#{Time.now}: "
    padding = " " * prefix.length
    first = true
    s.split(/[\r\n]/).each do |l|
      l = l.chomp
      if first
        first = false
        @mode << "#{prefix}#{l}\n"
      else
        @mode << "#{padding}#{l}\n"
      end
    end
    $stderr.puts "[#{Time.now}] #{s.chomp}" unless BufferManager.instantiated? && @mode.buffer
  end
  
  def self.method_missing m, *a
    @@instance = Logger.new unless @@instance
    @@instance.send m, *a
  end

  def self.buffer
    @@instance.buf
  end
end

end

