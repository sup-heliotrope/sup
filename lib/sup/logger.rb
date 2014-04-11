require "sup/util"
require 'stringio'
require 'thread'

module Redwood

## simple centralized logger. outputs to multiple sinks by calling << on them.
## also keeps a record of all messages, so that adding a new sink will send all
## previous messages to it by default.
class Logger
  include Redwood::Singleton

  LEVELS = %w(debug info warn error) # in order!

  def initialize level=nil
    level ||= ENV["SUP_LOG_LEVEL"] || "info"
    self.level = level
    @mutex = Mutex.new
    @buf = StringIO.new
    @sinks = []
  end

  def level; LEVELS[@level] end
  def level=(level); @level = LEVELS.index(level) || raise(ArgumentError, "invalid log level #{level.inspect}: should be one of #{LEVELS * ', '}"); end

  def add_sink s, copy_current=true
    @mutex.synchronize do
      @sinks << s
      s << @buf.string if copy_current
    end
  end

  def remove_sink s; @mutex.synchronize { @sinks.delete s } end
  def remove_all_sinks!; @mutex.synchronize { @sinks.clear } end
  def clear!; @mutex.synchronize { @buf = StringIO.new } end

  LEVELS.each_with_index do |l, method_level|
    define_method(l) do |s|
      if method_level >= @level
        send_message format_message(l, Time.now, s)
      end
    end
  end

  ## send a message regardless of the current logging level
  def force_message m; send_message format_message(nil, Time.now, m) end

private

  ## level can be nil!
  def format_message level, time, msg
    prefix = case level
      when "warn"; "WARNING: "
      when "error"; "ERROR: "
      else ""
    end
    "[#{time.to_s}] #{prefix}#{msg.rstrip}\n"
  end

  ## actually distribute the message
  def send_message m
    @mutex.synchronize do
      @sinks.each do |sink|
        sink << m
        sink.flush if sink.respond_to?(:flush) and level == "debug"
      end
      @buf << m
    end
  end
end

## include me to have top-level #debug, #info, etc. methods.
module LogsStuff
  Logger::LEVELS.each { |l| define_method(l) { |s| Logger.instance.send(l, s) } }
end

end
