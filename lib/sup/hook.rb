module Redwood

class HookManager
  class HookContext
    def initialize name
      @__say_id = nil
      @__name = name
      @__locals = {}
    end

    attr_writer :__locals
    def method_missing m, *a
      case @__locals[m]
      when Proc
        @__locals[m] = @__locals[m].call(*a) # only call the proc once
      when nil
        super
      else
        @__locals[m]
      end
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

    def __binding 
      binding
    end

    def __cleanup
      BufferManager.clear @__say_id if @__say_id
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
    context.__locals = locals

    result = nil
    begin
      result = context.instance_eval @hooks[name], fn_for(name)
    rescue Exception => e
      log "error running hook: #{e.message}"
      log e.backtrace.join("\n")
      @hooks[name] = nil # disable it
      BufferManager.flash "Error running hook: #{e.message}" if BufferManager.instantiated?
    end
    context.__cleanup
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
      @hooks[name] =
        begin
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
