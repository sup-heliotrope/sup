module Redwood

class DraftManager
  include Singleton

  attr_accessor :source
  def initialize dir
    @dir = dir
    @source = nil
    self.class.i_am_the_instance self
  end

  def self.source_name; "drafts"; end
  def self.source_id; 9999; end
  def new_source; @source = DraftLoader.new @dir; end

  def write_draft
    offset = @source.gen_offset
    fn = @source.fn_for_offset offset
    File.open(fn, "w") { |f| yield f }

    @source.each do |offset, labels|
      m = Message.new @source, offset, labels
      Index.add_message m
      UpdateManager.relay :add, m
    end
  end

  def discard mid
    docid, entry = Index.load_entry_for_id mid
    raise ArgumentError, "can't find entry for draft: #{mid.inspect}" unless entry
    raise ArgumentError, "not a draft: source id #{entry[:source_id].inspect}, should be #{DraftManager.source_id.inspect} for #{mid.inspect} / docno #{docid}" unless entry[:source_id].to_i == DraftManager.source_id
    Index.drop_entry docid
    File.delete @source.fn_for_offset(entry[:source_info])
    UpdateManager.relay :delete, mid
  end
end

class DraftLoader
  attr_accessor :dir, :end_offset
  bool_reader :dirty

  def initialize dir, end_offset=0
    Dir.mkdir dir unless File.exists? dir
    @dir = dir
    @end_offset = end_offset
    @dirty = false
  end

  def done?; !File.exists? fn_for_offset(@end_offset); end
  def usual?; true; end
  def id; DraftManager.source_id; end
  def to_s; DraftManager.source_name; end
  def is_source_for? x; x == DraftManager.source_name; end

  def gen_offset
    i = @end_offset
    while File.exists? fn_for_offset(i)
      i += 1
    end
    i
  end

  def fn_for_offset o; File.join(@dir, o.to_s); end

  def load_header offset
    File.open fn_for_offset(offset) do |f|
      return MBox::read_header(f)
    end
  end
  
  def load_message offset
    File.open fn_for_offset(offset) do |f|
      RMail::Mailbox::MBoxReader.new(f).each_message do |input|
        return RMail::Parser.read(input)
      end
    end
  end

  def raw_header offset
    ret = ""
    File.open fn_for_offset(offset) do |f|
      until f.eof? || (l = f.gets) =~ /^$/
        ret += l
      end
    end
    ret
  end

  def raw_full_message offset
    ret = ""
    File.open fn_for_offset(offset) do |f|
      ret += l until f.eof?
    end
    ret
  end

  def each
    while File.exists?(fn = File.join(@dir, @end_offset.to_s))
      yield @end_offset, [:draft, :inbox]
      @end_offset += 1
      @dirty = true
    end
  end

  def total; Dir[File.join(@dir, "*")].sort.last.to_i; end
  def reset!; @end_offset = 0; @dirty = true; end
end

Redwood::register_yaml(DraftLoader, %w(dir end_offset))

end
