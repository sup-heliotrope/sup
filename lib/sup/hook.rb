module Redwood

class HookManager
  ## there's probably a better way to do this, but to evaluate a hook
  ## with a bunch of pre-set "local variables" i define a function
  ## per variable and then instance_evaluate the code.
  ##
  ## how does rails do it, when you pass :locals into a partial?
  ##
  ## i don't bother providing setters, since i'm pretty sure the
  ## charade will fall apart pretty quickly with respect to scoping.
  ## this is basically fail-fast.
  class HookContext
    def initialize name
      @__name = name
      @__locals = {}
    end

    attr_writer :__locals

    def method_missing m, *a
      case @__locals[m]
      when Proc
        @__locals[m].call(*a)
      when nil
        super
      else
        @__locals[m]
      end
    end

    def say s
      @__say_id = BufferManager.say s, @__say_id
      BufferManager.draw_screen
    end

    def log s
      Redwood::log "hook[#@__name]: #{s}"
    end

    def ask_yes_or_no q
      BufferManager.ask_yes_or_no q
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
    
    Dir.mkdir dir unless File.exists? dir

    self.class.i_am_the_instance self
  end

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
      BufferManager.flash "Error running hook: #{e.message}"
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

private

  def hook_for name
    unless @hooks.member? name
      @hooks[name] =
        begin
          returning IO.readlines(fn_for(name)).join do
            log "read '#{name}' from #{fn_for(name)}"
          end
        rescue SystemCallError => e
          log "disabled hook for '#{name}': #{e.message}"
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
