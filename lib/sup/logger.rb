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
    @mode.buffer = BufferManager.instance.spawn "<log>", @mode, :hidden => true
    @spawning = false
  end

  def log s
#    $stderr.puts s
    make_buf
    @mode << "#{Time.now}: #{s.chomp}\n"
    $stderr.puts "[#{Time.now}] #{s.chomp}" unless @mode.buffer
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
