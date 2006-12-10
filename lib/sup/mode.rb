module Redwood

class Mode
  attr_accessor :buffer
  @@keymaps = {}

  def self.register_keymap keymap=nil, &b
    keymap = Keymap.new(&b) if keymap.nil?
    @@keymaps[self] = keymap
  end

  def initialize
    @buffer = nil
  end

  def self.make_name s; s.gsub(/.*::/, "").camel_to_hyphy; end
  def name; Mode.make_name self.class.name; end

  def self.load_all_modes dir
    Dir[File.join(dir, "*.rb")].each do |f|
      $stderr.puts "## loading mode #{f}"
      require f
    end
  end

  def killable?; true; end
  def draw; end
  def focus; end
  def blur; end
  def status; ""; end
  def resize rows, cols; end
  def cleanup
    @buffer = nil
  end

  ## turns an input keystroke into an action symbol
  def resolve_input c
    ## try all keymaps in order of age
    action = nil
    klass = self.class

    ancestors.each do |klass|
      action = @@keymaps.member?(klass) && @@keymaps[klass].action_for(c)
      return action if action
    end

    nil
  end

  def handle_input c
    if(action = resolve_input c)
      send action
      true
    else
      false
    end
  end

  def help_text
    used_keys = {}
    ancestors.map do |klass|
      km = @@keymaps[klass] or next
      title = "Keybindings from #{Mode.make_name klass.name}"
      s = <<EOS
#{title}
#{'-' * title.length}

#{km.help_text used_keys}
EOS
      begin
        used_keys.merge! km.keysyms.to_boolean_h
      rescue ArgumentError
        raise km.keysyms.inspect
      end
      s
    end.compact.join "\n"
  end
end

end
