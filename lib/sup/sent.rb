module Redwood

class SentManager
  include Singleton

  attr_accessor :source
  def initialize fn
    @fn = fn
    @source = nil
    self.class.i_am_the_instance self
  end

  def self.source_name; "sent"; end
  def self.source_id; 9998; end
  def new_source; @source = SentLoader.new @fn; end

  def write_sent_message date, from_email
    need_blank = File.exists?(@fn) && !File.zero?(@fn)
    File.open(@fn, "a") do |f|
      if need_blank
        @source.increment_offset if @source.offset == f.tell
        f.puts
      end
      f.puts "From #{from_email} #{date}"
      yield f
    end
    @source.each do |offset, labels|
      m = Message.new @source, offset, labels
      Index.add_message m
      UpdateManager.relay :add, m
    end
  end
end

class SentLoader < MBox::Loader
  def initialize filename, end_offset=0
    File.open(filename, "w") { } unless File.exists? filename
    super filename, end_offset, true, true
  end

  def increment_offset; @end_offset += 1; end
  def offset; @end_offset; end
  def id; SentManager.source_id; end
  def to_s; SentManager.source_name; end

  def labels; [:sent, :inbox]; end
end

Redwood::register_yaml(SentLoader, %w(filename end_offset))

end
