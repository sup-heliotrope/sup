module Redwood

class HookManager
  class HookContext
    def initialize name
      @__say_id = nil
      @__name = name
    end

    def say s
      if BufferManager.instantiated?
        @__say_id = BufferManager.say s, @__say_id
        BufferManager.draw_screen
      else
        log s
      end
    end

    def log s
      Redwood::log "hook[#@__name]: #{s}"
    end

    def ask_yes_or_no q
      if BufferManager.instantiated?
        BufferManager.ask_yes_or_no q
      else
        print q
        gets.chomp.downcase == 'y'
      end
    end

    def get tag
      HookManager.tags[tag]
    end

    def set tag, value
      HookManager.tags[tag] = value
    end

    def __run __hook, __filename, __locals
      __binding = binding
      eval __locals.map { |k, v| "#{k} = __locals[#{k.inspect}];" }.join, __binding
      ret = eval __hook, __binding, __filename
      BufferManager.clear @__say_id if @__say_id
      ret
    end
  end

  include Singleton

  def initialize dir
    @dir = dir
    @hooks = {}
    @descs = {}
    @contexts = {}
    @tags = {}

    Dir.mkdir dir unless File.exists? dir

    self.class.i_am_the_instance self
  end

  attr_reader :tags

  def run name, locals={}
    hook = hook_for(name) or return
    context = @contexts[hook] ||= HookContext.new(name)

    result = nil
    begin
      result = context.__run hook, fn_for(name), locals
    rescue Exception => e
      log "error running hook: #{e.message}"
      log e.backtrace.join("\n")
      @hooks[name] = nil # disable it
      BufferManager.flash "Error running hook: #{e.message}" if BufferManager.instantiated?
    end
    result
  end

  def register name, desc
    @descs[name] = desc
  end

  def print_hooks f=$stdout
puts <<EOS
Have #{@descs.size} registered hooks:

EOS

    @descs.sort.each do |name, desc|
      f.puts <<EOS
#{name}
#{"-" * name.length}
File: #{fn_for name}
#{desc}
EOS
    end
  end

  def enabled? name; !hook_for(name).nil? end

private

  def hook_for name
    unless @hooks.member? name
      @hooks[name] = begin
        returning IO.read(fn_for(name)) do
          log "read '#{name}' from #{fn_for(name)}"
        end
      rescue SystemCallError => e
        #log "disabled hook for '#{name}': #{e.message}"
        nil
      end
    end

    @hooks[name]
  end

  def fn_for name
    File.join @dir, "#{name}.rb"
  end

  def log m
    Redwood::log("hook: " + m)
  end
end

end
