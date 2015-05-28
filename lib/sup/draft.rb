module Redwood

class DraftManager
  include Redwood::Singleton

  attr_accessor :source
  def initialize dir
    @dir = dir
    @source = nil
  end

  def self.source_name; "sup://drafts"; end
  def self.source_id; 9999; end
  def new_source; @source = DraftLoader.new; end

  def write_draft
    offset = @source.gen_offset
    fn = @source.fn_for_offset offset
    File.open(fn, "w:UTF-8") { |f| yield f }
    PollManager.poll_from @source
  end

  def discard m
    raise ArgumentError, "not a draft: source id #{m.source.id.inspect}, should be #{DraftManager.source_id.inspect} for #{m.id.inspect}" unless m.source.id.to_i == DraftManager.source_id
    Index.delete m.id
    File.delete @source.fn_for_offset(m.source_info) rescue Errono::ENOENT
    UpdateManager.relay self, :single_message_deleted, m
  end
end

class DraftLoader < Source
  attr_accessor :dir
  yaml_properties

  def initialize dir=Redwood::DRAFT_DIR
    Dir.mkdir dir unless File.exist? dir
    super DraftManager.source_name, true, false
    @dir = dir
    @cur_offset = 0
  end

  def properly_initialized?
    !!(@dir && @cur_offset)
  end

  def id; DraftManager.source_id; end
  def to_s; DraftManager.source_name; end
  def uri; DraftManager.source_name; end

  def poll
    ids = get_ids
    ids.each do |id|
      if id >= @cur_offset
        @cur_offset = id + 1
        yield :add,
          :info => id,
          :labels => [:draft, :inbox],
          :progress => 0.0
      end
    end
  end

  def gen_offset
    i = @cur_offset
    while File.exist? fn_for_offset(i)
      i += 1
    end
    i
  end

  def fn_for_offset o; File.join(@dir, o.to_s); end

  def load_header offset
    File.open(fn_for_offset(offset)) { |f| parse_raw_email_header f }
  end

  def load_message offset
    raise SourceError, "Draft not found" unless File.exist? fn_for_offset(offset)
    File.open fn_for_offset(offset) do |f|
      RMail::Mailbox::MBoxReader.new(f).each_message do |input|
        return RMail::Parser.read(input)
      end
    end
  end

  def raw_header offset
    ret = ""
    File.open(fn_for_offset(offset), "r:UTF-8") do |f|
      until f.eof? || (l = f.gets) =~ /^$/
        ret += l
      end
    end
    ret
  end

  def each_raw_message_line offset
    File.open(fn_for_offset(offset), "r:UTF-8") do |f|
      yield f.gets until f.eof?
    end
  end

  def raw_message offset
    IO.read(fn_for_offset(offset), :encoding => "UTF-8")
  end

  def start_offset; 0; end
  def end_offset
    ids = get_ids
    ids.empty? ? 0 : (ids.last + 1)
  end

private

  def get_ids
    Dir.entries(@dir).select { |x| x =~ /^\d+$/ }.map { |x| x.to_i }.sort
  end
end

end
