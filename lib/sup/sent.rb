module Redwood

class SentManager
  include Singleton

  attr_accessor :source
  def initialize fn
    @fn = fn
    @source = nil
    self.class.i_am_the_instance self
  end

  def self.source_name; "sup://sent"; end
  def self.source_id; 9998; end
  def new_source; @source = Recoverable.new SentLoader.new; end

  def write_sent_message date, from_email
    need_blank = File.exists?(@fn) && !File.zero?(@fn)
    File.open(@fn, "a") do |f|
      f.puts if need_blank
      f.puts "From #{from_email} #{date}"
      yield f
    end

    @source.each do |offset, labels|
      m = Message.new :source => @source, :source_info => offset, :labels => @source.labels
      Index.sync_message m
      UpdateManager.relay self, :add, m
    end
  end
end

class SentLoader < MBox::Loader
  yaml_properties :cur_offset

  def initialize cur_offset=0
    @filename = Redwood::SENT_FN
    File.open(@filename, "w") { } unless File.exists? @filename
    super "mbox://" + @filename, cur_offset, true, true
  end

  def file_path; @filename end

  def uri; SentManager.source_name; end
  def to_s; SentManager.source_name; end
  def id; SentManager.source_id; end
  def labels; [:sent, :inbox]; end
end

end
