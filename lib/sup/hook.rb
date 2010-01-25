module Redwood

class HookManager
  class HookContext
    def initialize name
      @__say_id = nil
      @__name = name
      @__cache = {}
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
      info "hook[#@__name]: #{s}"
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
      __lprocs, __lvars = __locals.partition { |k, v| v.is_a?(Proc) }
      eval __lvars.map { |k, v| "#{k} = __locals[#{k.inspect}];" }.join, __binding
      ## we also support closures for delays evaluation. unfortunately
      ## we have to do this via method calls, so you don't get all the
      ## semantics of a regular variable. not ideal.
      __lprocs.each do |k, v|
        self.class.instance_eval do
          define_method k do
            @__cache[k] ||= v.call
          end
        end
      end
      ret = eval __hook, __binding, __filename
      BufferManager.clear @__say_id if @__say_id
      @__cache = {}
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
  end

  attr_reader :tags

  def run name, locals={}
    hook = hook_for(name) or return
    context = @contexts[hook] ||= HookContext.new(name)

    result = nil
    fn = fn_for name
    begin
      result = context.__run hook, fn, locals
    rescue Exception => e
      log "error running #{fn}: #{e.message}"
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

  def clear; @hooks.clear; end
  def clear_one k; @hooks.delete k; end

private

  def hook_for name
    unless @hooks.member? name
      @hooks[name] = begin
        returning IO.read(fn_for(name)) do
          debug "read '#{name}' from #{fn_for(name)}"
        end
      rescue SystemCallError => e
        #debug "disabled hook for '#{name}': #{e.message}"
        nil
      end
    end

    @hooks[name]
  end

  def fn_for name
    File.join @dir, "#{name}.rb"
  end

  def log m
    info("hook: " + m)
  end
end

end
