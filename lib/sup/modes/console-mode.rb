require 'pp'

module Redwood

class Console
  def initialize mode
    @mode = mode
  end

  def query(query)
    Enumerable::Enumerator.new(Index, :each_message, Index.parse_query(query))
  end

  def add_labels(query, *labels)
    query(query).each { |m| m.labels += labels; m.save Index }
  end

  def remove_labels(query, *labels)
    query(query).each { |m| m.labels -= labels; m.save Index }
  end
end

class ConsoleMode < LogMode
  def initialize
    super
    @binding = Console.new(self).instance_eval { binding }
  end

  def execute cmd
    begin
      self << ">> #{cmd}\n"
      ret = eval cmd, @binding
      self << "=> #{ret.pretty_inspect}\n"
    rescue Exception
      self << "#{$!.class}: #{$!.message}\n"
      clean_backtrace = []
      $!.backtrace.each { |l| break if l =~ /console-mode/; clean_backtrace << l }
      clean_backtrace.each { |l| self << "#{l}\n" }
    end
  end

  def prompt
    BufferManager.ask :console, "eval: "
  end

  def run
    while true
      cmd = prompt or return
      execute cmd
    end
  end
end

end
