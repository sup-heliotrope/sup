module Redwood

class HookManager

  ## there's probably a better way to do this, but to evaluate a hook
  ## with a bunch of pre-set "local variables" i define a function
  ## per variable and then instance_evaluate the code.
  ##
  ## i don't bother providing setters, since i'm pretty sure the
  ## charade will fall apart pretty quickly with respect to scoping.
  ## this is basically fail-fast.
  class HookContext
    def initialize name, hash
      @__name = name
      hash.each do |k, v|
        self.class.instance_eval { define_method(k) { v } }
      end
    end

    def say s
      @__say_id = BufferManager.say s, @__say_id
    end

    def log s
      Redwood::log "hook[#@__name]: #{s}"
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
    Dir.mkdir dir unless File.exists? dir

    self.class.i_am_the_instance self
  end

  def run name, locals={}
    hook = hook_for(name) or return
    context = HookContext.new name, locals

    begin
      result = eval @hooks[name], context.__binding, fn_for(name)
      if result.is_a? String
        log "got return value: #{result.inspect}"
        BufferManager.flash result 
      end
    rescue Exception => e
      log "error running hook: #{e.message}"
      BufferManager.flash "Error running hook: #{e.message}"
    end
    context.__cleanup
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
