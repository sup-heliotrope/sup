require 'pathname'

module Redwood

## meant to be spawned via spawn_modal!
class FileBrowserMode < LineCursorMode
  RESERVED_ROWS = 1

  register_keymap do |k|
    k.add :back, "Go back to previous directory", "B"
    k.add :view, "View file", "v"
    k.add :select_file_or_follow_directory, "Select the highlighted file, or follow the directory", :enter
    k.add :reload, "Reload file list", "R"
  end

  bool_reader :done
  attr_reader :value

  def initialize dir="."
    @dirs = [Pathname.new(dir).realpath]
    @done = false
    @value = nil
    regen_text
    super :skip_top_rows => RESERVED_ROWS
  end

  def cwd; @dirs.last end
  def lines; @text.length; end
  def [] i; @text[i]; end

protected

  def back
    return if @dirs.size == 1
    @dirs.pop
    reload
  end

  def reload
    regen_text
    jump_to_start
    buffer.mark_dirty
  end

  def view
     name, f = @files[curpos - RESERVED_ROWS]
    return unless f && f.file?

    begin
      BufferManager.spawn f.to_s, TextMode.new(f.read.ascii)
    rescue SystemCallError => e
      BufferManager.flash e.message
    end
  end

  def select_file_or_follow_directory
    name, f = @files[curpos - RESERVED_ROWS]
    return unless f

    if f.directory? && f.to_s != "."
      if f.readable?
        @dirs.push f
        reload
      else
        BufferManager.flash "Permission denied - #{f.realpath}"
      end
    else
      begin
        @value = f.realpath.to_s
        @done = true
      rescue SystemCallError => e
        BufferManager.flash e.message
      end
    end
  end

  def regen_text
    @files =
      begin
        cwd.entries.sort_by do |f|
          [f.directory? ? 0 : 1, f.basename.to_s]
        end
      rescue SystemCallError => e
        BufferManager.flash "Error: #{e.message}"
        [Pathname.new("."), Pathname.new("..")]
      end.map do |f|
      real_f = cwd + f
      name = f.basename.to_s +
        case
        when real_f.symlink?
          "@"
        when real_f.directory?
          "/"
        else
          ""
        end
      [name, real_f]
    end

    size_width = @files.max_of { |name, f| f.human_size.length }
    time_width = @files.max_of { |name, f| f.human_time.length }

    @text = ["#{cwd}:"] + @files.map do |name, f|
      sprintf "%#{time_width}s %#{size_width}s %s", f.human_time, f.human_size, name
    end
  end
end

end
