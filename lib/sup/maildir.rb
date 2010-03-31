require 'rmail'
require 'uri'

module Redwood

class Maildir < Source
  include SerializeLabelsNicely
  MYHOSTNAME = Socket.gethostname

  ## remind me never to use inheritance again.
  yaml_properties :uri, :usual, :archived, :id, :labels
  def initialize uri, usual=true, archived=false, id=nil, labels=[]
    super uri, usual, archived, id
    uri = URI(Source.expand_filesystem_uri(uri))

    raise ArgumentError, "not a maildir URI" unless uri.scheme == "maildir"
    raise ArgumentError, "maildir URI cannot have a host: #{uri.host}" if uri.host
    raise ArgumentError, "maildir URI must have a path component" unless uri.path

    @dir = uri.path
    @labels = Set.new(labels || [])
    @mutex = Mutex.new
    @mtimes = { 'cur' => Time.at(0), 'new' => Time.at(0) }
  end

  def file_path; @dir end
  def self.suggest_labels_for path; [] end
  def is_source_for? uri; super || (URI(Source.expand_filesystem_uri(uri)) == URI(self.uri)); end

  def store_message date, from_email, &block
    stored = false
    new_fn = new_maildir_basefn + ':2,S'
    Dir.chdir(@dir) do |d|
      tmp_path = File.join(@dir, 'tmp', new_fn)
      new_path = File.join(@dir, 'new', new_fn)
      begin
        sleep 2 if File.stat(tmp_path)

        File.stat(tmp_path)
      rescue Errno::ENOENT #this is what we want.
        begin
          File.open(tmp_path, 'wb') do |f|
            yield f #provide a writable interface for the caller
            f.fsync
          end

          File.link tmp_path, new_path
          stored = true
        ensure
          File.unlink tmp_path if File.exists? tmp_path
        end
      end #rescue Errno...
    end #Dir.chdir

    stored
  end

  def each_raw_message_line id
    with_file_for(id) do |f|
      until f.eof?
        yield f.gets
      end
    end
  end

  def load_header id
    with_file_for(id) { |f| parse_raw_email_header f }
  end

  def load_message id
    with_file_for(id) { |f| RMail::Parser.read f }
  end

  def raw_header id
    ret = ""
    with_file_for(id) do |f|
      until f.eof? || (l = f.gets) =~ /^$/
        ret += l
      end
    end
    ret
  end

  def raw_message id
    with_file_for(id) { |f| f.read }
  end

  ## XXX use less memory
  def poll
    @mtimes.each do |d,prev_mtime|
      subdir = File.join @dir, d
      raise FatalSourceError, "#{subdir} not a directory" unless File.directory? subdir
      mtime = File.mtime subdir
      next if prev_mtime >= mtime
      @mtimes[d] = mtime

      old_ids = benchmark(:index) { Enumerator.new(Index, :each_source_info, self.id, "#{d}/").to_a }
      new_ids = benchmark(:glob) { Dir.glob("#{subdir}/*").map { |x| File.basename x }.sort }
      added = new_ids - old_ids
      deleted = old_ids - new_ids
      debug "#{added.size} added, #{deleted.size} deleted"

      added.each do |id|
        yield :add,
          :info => File.join(d,id),
          :labels => @labels + maildir_labels(id) + [:inbox],
          :progress => 0.0
      end

      deleted.each do |id|
        yield :delete,
          :info => File.join(d,id),
          :progress => 0.0
      end
    end
    nil
  end

  def maildir_labels id
    (seen?(id) ? [] : [:unread]) +
      (trashed?(id) ?  [:deleted] : []) +
      (flagged?(id) ? [:starred] : [])
  end

  def draft? id; maildir_data(id)[2].include? "D"; end
  def flagged? id; maildir_data(id)[2].include? "F"; end
  def passed? id; maildir_data(id)[2].include? "P"; end
  def replied? id; maildir_data(id)[2].include? "R"; end
  def seen? id; maildir_data(id)[2].include? "S"; end
  def trashed? id; maildir_data(id)[2].include? "T"; end

  def mark_draft id; maildir_mark_file id, "D" unless draft? id; end
  def mark_flagged id; maildir_mark_file id, "F" unless flagged? id; end
  def mark_passed id; maildir_mark_file id, "P" unless passed? id; end
  def mark_replied id; maildir_mark_file id, "R" unless replied? id; end
  def mark_seen id; maildir_mark_file id, "S" unless seen? id; end
  def mark_trashed id; maildir_mark_file id, "T" unless trashed? id; end

private

  def new_maildir_basefn
    Kernel::srand()
    "#{Time.now.to_i.to_s}.#{$$}#{Kernel.rand(1000000)}.#{MYHOSTNAME}"
  end

  def with_file_for id
    begin
      File.open(File.join(@dir, id), 'rb') { |f| yield f }
    rescue SystemCallError, IOError => e
      raise FatalSourceError, "Problem reading file for id #{id.inspect}: #{fn.inspect}: #{e.message}."
    end
  end

  def maildir_data id
    id =~ %r{^([^:]+):([12]),([DFPRST]*)$}
    [($1 || id), ($2 || "2"), ($3 || "")]
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
