require "sup/util"

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

    def flash s
      if BufferManager.instantiated?
        BufferManager.flash s
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

  include Redwood::Singleton

  @descs = {}

  class << self
    attr_reader :descs
  end

  def initialize dir
    @dir = dir
    @hooks = {}
    @contexts = {}
    @tags = {}

    Dir.mkdir dir unless File.exist? dir
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

  def self.register name, desc
    @descs[name] = desc
  end

  def print_hooks pattern="", f=$stdout
    matching_hooks = HookManager.descs.sort.keep_if {|name, desc| pattern.empty? or name.match(pattern)}.map do |name, desc|
      <<EOS
#{name}
#{"-" * name.length}
File: #{fn_for name}
#{desc}
EOS
    end

    showing_str = matching_hooks.size == HookManager.descs.size ? "" : " (showing #{matching_hooks.size})"
    f.puts "Have #{HookManager.descs.size} registered hooks#{showing_str}:"
    f.puts
    matching_hooks.each { |text| f.puts text }
  end

  def enabled? name; !hook_for(name).nil? end

  def clear; @hooks.clear; BufferManager.flash "Hooks cleared" end
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
