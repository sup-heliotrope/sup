require 'pp'

module Redwood

class Console
  def initialize mode
    @mode = mode
  end

  def query(query)
    Enumerator.new(Index.instance, :each_message, Index.parse_query(query))
  end

  def add_labels(query, *labels)
    count = 0
    query(query).each do |m|
      labels.each {|l| m.add_label l }
      Index.update_message_state m
      count += 1
    end
    Index.save_index
    puts "Labels modified on #{count} messages."
    puts "You might want to refresh open buffer with `@` key."
  end

  def remove_labels(query, *labels)
    count = 0
    query(query).each do |m|
      labels.each {|l| m.remove_label l }
      Index.update_message_state m
      count += 1
    end
    Index.save_index
    puts "Labels modified on #{count} messages."
    puts "You might want to refresh open buffer with `@` key."
  end

  def xapian; Index.instance.instance_variable_get :@xapian; end

  def loglevel; Redwood::Logger.level; end
  def set_loglevel(level); Redwood::Logger.level = level; end

  def special_methods; methods - Object.methods end

  def puts x; @mode << "#{x.to_s.rstrip}\n" end
  def p x; puts x.inspect end

  ## files that won't cause problems when reloaded
  ## TODO expand this list / convert to blacklist
  RELOAD_WHITELIST = %w(sup/index.rb sup/modes/console-mode.rb)

  def reload
    old_verbose = $VERBOSE
    $VERBOSE = nil
    old_features = $".dup
    begin
      fs = $".grep(/^sup\//)
      fs.reject! { |f| not RELOAD_WHITELIST.member? f }
      fs.each { |f| $".delete f }
      fs.each do |f|
        @mode << "reloading #{f}\n"
        begin
          require f
        rescue LoadError => e
          raise unless e.message =~ /no such file to load/
        end
      end
    rescue Exception
      $".clear
      $".concat old_features
      raise
    ensure
      $VERBOSE = old_verbose
    end
    true
  end

  def clear_hooks
    HookManager.clear
    nil
  end
end

class ConsoleMode < LogMode
  register_keymap do |k|
    k.add :run, "Restart evaluation", 'e'
  end

  def initialize
    super "console"
    @console = Console.new self
    @binding = @console.instance_eval { binding }
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
    BufferManager.ask :console, ">> "
  end

  def run
    self << <<EOS
Sup v#{VERSION} console session started.
Available extra commands: #{(@console.special_methods) * ", "}
Ctrl-G stops evaluation; 'e' restarts it.

EOS
    while true
      if(cmd = prompt)
        execute cmd
      else
        self << "Console session ended."
        break
      end
    end
  end
end

end
