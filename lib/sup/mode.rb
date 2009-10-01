require 'open3'
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
  def unsaved?; false end
  def draw; end
  def focus; end
  def blur; end
  def cancel_search!; end
  def in_search?; false end
  def status; ""; end
  def resize rows, cols; end
  def cleanup
    @buffer = nil
  end

  def resolve_input c
    ancestors.each do |klass| # try all keymaps in order of ancestry
      next unless @@keymaps.member?(klass)
      action = BufferManager.resolve_input_with_keymap c, @@keymaps[klass]
      return action if action
    end
    nil
  end

  def handle_input c
    action = resolve_input(c) or return false
    send action
    true
  end

  def help_text
    used_keys = {}
    ancestors.map do |klass|
      km = @@keymaps[klass] or next
      title = "Keybindings from #{Mode.make_name klass.name}"
      s = <<EOS
#{title}
#{'-' * title.display_length}

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

### helper functions

  def save_to_file fn, talk=true
    if File.exists? fn
      unless BufferManager.ask_yes_or_no "File \"#{fn}\" exists. Overwrite?"
        info "Not overwriting #{fn}"
        return
      end
    end
    begin
      File.open(fn, "w") { |f| yield f }
      BufferManager.flash "Successfully wrote #{fn}." if talk
      true
    rescue SystemCallError, IOError => e
      m = "Error writing file: #{e.message}"
      info m
      BufferManager.flash m
      false
    end
  end

  def pipe_to_process command
    Open3.popen3(command) do |input, output, error|
      err, data, * = IO.select [error], [input], nil

      unless err.empty?
        message = err.first.read
        if message =~ /^\s*$/
          warn "error running #{command} (but no error message)"
          BufferManager.flash "Error running #{command}!"
        else
          warn "error running #{command}: #{message}"
          BufferManager.flash "Error: #{message}"
        end
        return
      end

      data = data.first
      data.sync = false # buffer input

      yield data
      data.close # output will block unless input is closed

      ## BUG?: shows errors or output but not both....
      data, * = IO.select [output, error], nil, nil
      data = data.first

      if data.eof
        BufferManager.flash "'#{command}' done!"
        nil
      else
        data.read
      end
    end
  end
end

end
