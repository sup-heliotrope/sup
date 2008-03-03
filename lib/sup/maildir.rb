require 'rmail'
require 'uri'

module Redwood

## Maildir doesn't provide an ordered unique id, which is what Sup
## requires to be really useful. So we must maintain, in memory, a
## mapping between Sup "ids" (timestamps, essentially) and the
## pathnames on disk.

class Maildir < Source
  SCAN_INTERVAL = 30 # seconds

  ## remind me never to use inheritance again.
  yaml_properties :uri, :cur_offset, :usual, :archived, :id, :labels
  def initialize uri, last_date=nil, usual=true, archived=false, id=nil, labels=[]
    super uri, last_date, usual, archived, id
    uri = URI(Source.expand_filesystem_uri(uri))

    raise ArgumentError, "not a maildir URI" unless uri.scheme == "maildir"
    raise ArgumentError, "maildir URI cannot have a host: #{uri.host}" if uri.host
    raise ArgumentError, "mbox URI must have a path component" unless uri.path

    @dir = uri.path
    @labels = (labels || []).freeze
    @ids = []
    @ids_to_fns = {}
    @last_scan = nil
    @mutex = Mutex.new
  end

  def file_path; @dir end
  def self.suggest_labels_for path; [] end
  def is_source_for? uri; super || (URI(Source.expand_filesystem_uri(uri)) == URI(self.uri)); end

  def check
    scan_mailbox
    return unless start_offset

    start = @ids.index(cur_offset || start_offset) or raise OutOfSyncSourceError, "Unknown message id #{cur_offset || start_offset}." # couldn't find the most recent email
  end
  
  def each_raw_message_line id
    scan_mailbox
    with_file_for(id) do |f|
      until f.eof?
        yield f.gets
      end
    end
  end

  def load_header id
    scan_mailbox
    with_file_for(id) { |f| MBox::read_header f }
  end

  def load_message id
    scan_mailbox
    with_file_for(id) { |f| RMail::Parser.read f }
  end

  def raw_header id
    scan_mailbox
    ret = ""
    with_file_for(id) do |f|
      until f.eof? || (l = f.gets) =~ /^$/
        ret += l
      end
    end
    ret
  end

  def raw_message id
    scan_mailbox
    with_file_for(id) { |f| f.readlines.join }
  end

  def scan_mailbox opts={}
    return unless @ids.empty? || opts[:rescan]
    return if @last_scan && (Time.now - @last_scan) < SCAN_INTERVAL

    Redwood::log "scanning maildir..."
    cdir = File.join(@dir, 'cur')
    ndir = File.join(@dir, 'new')
    
    raise FatalSourceError, "#{cdir} not a directory" unless File.directory? cdir
    raise FatalSourceError, "#{ndir} not a directory" unless File.directory? ndir

    begin
      @ids, @ids_to_fns = [], {}
      (Dir[File.join(cdir, "*")] + Dir[File.join(ndir, "*")]).map do |fn|
        id = make_id fn
        @ids << id
        @ids_to_fns[id] = fn
      end
      @ids.sort!
    rescue SystemCallError, IOError => e
      raise FatalSourceError, "Problem scanning Maildir directories: #{e.message}."
    end
    
    Redwood::log "done scanning maildir"
    @last_scan = Time.now
  end
  synchronized :scan_mailbox

  def each
    scan_mailbox
    return unless start_offset

    start = @ids.index(cur_offset || start_offset) or raise OutOfSyncSourceError, "Unknown message id #{cur_offset || start_offset}." # couldn't find the most recent email

    start.upto(@ids.length - 1) do |i|         
      id = @ids[i]
      self.cur_offset = id
      yield id, @labels + (seen?(id) ? [] : [:unread]) + (trashed?(id) ? [:deleted] : []) + (flagged?(id) ? [:starred] : [])
    end
  end

  def start_offset
    scan_mailbox
    @ids.first
  end

  def end_offset
    scan_mailbox :rescan => true
    @ids.last + 1
  end

  def pct_done; 100.0 * (@ids.index(cur_offset) || 0).to_f / (@ids.length - 1).to_f; end

  def draft? msg; maildir_data(msg)[2].include? "D"; end
  def flagged? msg; maildir_data(msg)[2].include? "F"; end
  def passed? msg; maildir_data(msg)[2].include? "P"; end
  def replied? msg; maildir_data(msg)[2].include? "R"; end
  def seen? msg; maildir_data(msg)[2].include? "S"; end
  def trashed? msg; maildir_data(msg)[2].include? "T"; end

  def mark_draft msg; maildir_mark_file msg, "D" unless draft? msg; end
  def mark_flagged msg; maildir_mark_file msg, "F" unless flagged? msg; end
  def mark_passed msg; maildir_mark_file msg, "P" unless passed? msg; end
  def mark_replied msg; maildir_mark_file msg, "R" unless replied? msg; end
  def mark_seen msg; maildir_mark_file msg, "S" unless seen? msg; end
  def mark_trashed msg; maildir_mark_file msg, "T" unless trashed? msg; end

private

  def make_id fn
    # use 7 digits for the size. why 7? seems nice.
    sprintf("%d%07d", File.mtime(fn), File.size(fn) % 10000000).to_i
  end

  def with_file_for id
    fn = @ids_to_fns[id] or raise OutOfSyncSourceError, "No such id: #{id.inspect}."
    begin
      File.open(fn) { |f| yield f }
    rescue SystemCallError, IOError => e
      raise FatalSourceError, "Problem reading file for id #{id.inspect}: #{fn.inspect}: #{e.message}."
    end
  end

  def maildir_data msg
    fn = File.basename @ids_to_fns[msg]
    fn =~ %r{^([^:,]+):([12]),([DFPRST]*)$}
    [($1 || fn), ($2 || "2"), ($3 || "")]
  end

  ## not thread-safe on msg
  def maildir_mark_file msg, flag
    orig_path = @ids_to_fns[msg]
    orig_base, orig_fn = File.split(orig_path)
    new_base = orig_base.slice(0..-4) + 'cur'
    tmp_base = orig_base.slice(0..-4) + 'tmp'
    md_base, md_ver, md_flags = maildir_data msg
    md_flags += flag; md_flags = md_flags.split(//).sort.join.squeeze
    new_path = File.join new_base, "#{md_base}:#{md_ver},#{md_flags}"
    tmp_path = File.join tmp_base, "#{md_base}:#{md_ver},#{md_flags}"
    File.link orig_path, tmp_path
    File.unlink orig_path
    File.link tmp_path, new_path
    File.unlink tmp_path
    @ids_to_fns[msg] = new_path
  end
end

end
