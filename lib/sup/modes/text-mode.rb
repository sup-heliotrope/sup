module Redwood

class TextMode < ScrollMode
  include M17n

  attr_reader :text
  register_keymap do |k|
    km = m('text.keymap')
    k.add :save_to_disk, km['save_to_disk'], 's'
    k.add :pipe, km['pipe'], '|'
  end

  def initialize text="", filename=nil
    @text = text
    @filename = filename
    update_lines
    buffer.mark_dirty if buffer
    super()
  end

  def save_to_disk
    fn = BufferManager.ask_for_filename :filename, "#{m('text.ask.for_filename')}: ", @filename
    save_to_file(fn) { |f| f.puts text } if fn
  end

  def pipe
    command = BufferManager.ask(:shell, "#{m('text.ask.pipe_command')}: ")
    return if command.nil? || command.empty?

    output = pipe_to_process(command) do |stream|
      @text.each { |l| stream.puts l }
    end

    if output
      BufferManager.spawn "#{m('text.output_of')} '#{command}'", TextMode.new(output)
    else
      BufferManager.flash "'#{command}' #{m('words.done')}!"
    end
  end

  def text= t
    @text = t
    update_lines
    if buffer
      ensure_mode_validity
      buffer.mark_dirty
    end
  end

  def << line
    @lines = [0] if @text.empty?
    @text << line
    @lines << @text.length
    if buffer
      ensure_mode_validity
      buffer.mark_dirty
    end
  end

  def lines
    @lines.length - 1
  end

  def [] i
    return nil unless i < @lines.length
    @text[@lines[i] ... (i + 1 < @lines.length ? @lines[i + 1] - 1 : @text.length)].normalize_whitespace
#    (@lines[i] ... (i + 1 < @lines.length ? @lines[i + 1] - 1 : @text.length)).inspect
  end

private

  def update_lines
    pos = @text.find_all_positions("\n")
    pos.push @text.length unless pos.last == @text.length - 1
    @lines = [0] + pos.map { |x| x + 1 }
  end
end

end
