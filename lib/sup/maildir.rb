require 'uri'

module Redwood

class Maildir < Source
  include SerializeLabelsNicely
  MYHOSTNAME = Socket.gethostname

  ## remind me never to use inheritance again.
  yaml_properties :uri, :usual, :archived, :id, :labels
  def initialize uri, usual=true, archived=false, id=nil, labels=[]
    super uri, usual, archived, id
    @expanded_uri = Source.expand_filesystem_uri(uri)
    uri = URI(@expanded_uri)

    raise ArgumentError, "not a maildir URI" unless uri.scheme == "maildir"
    raise ArgumentError, "maildir URI cannot have a host: #{uri.host}" if uri.host
    raise ArgumentError, "maildir URI must have a path component" unless uri.path

    @dir = uri.path
    @labels = Set.new(labels || [])
    @mutex = Mutex.new
    @ctimes = { 'cur' => Time.at(0), 'new' => Time.at(0) }
  end

  def file_path; @dir end
  def self.suggest_labels_for path; [] end
  def is_source_for? uri; super || (uri == @expanded_uri); end

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
    added = []
    deleted = []
    updated = []
    @ctimes.each do |d,prev_ctime|
      subdir = File.join @dir, d
      debug "polling maildir #{subdir}"
      raise FatalSourceError, "#{subdir} not a directory" unless File.directory? subdir
      ctime = File.ctime subdir
      next if prev_ctime >= ctime
      @ctimes[d] = ctime

      old_ids = benchmark(:maildir_read_index) { Enumerator.new(Index.instance, :each_source_info, self.id, "#{d}/").to_a }
      new_ids = benchmark(:maildir_read_dir) { Dir.glob("#{subdir}/*").map { |x| File.join(d,File.basename(x)) }.sort }
      added += new_ids - old_ids
      deleted += old_ids - new_ids
      debug "#{old_ids.size} in index, #{new_ids.size} in filesystem"
    end

    ## find updated mails by checking if an id is in both added and
    ## deleted arrays, meaning that its flags changed or that it has
    ## been moved, these ids need to be removed from added and deleted
    add_to_delete = del_to_delete = []
    added.each do |id_add|
      deleted.each do |id_del|
        if maildir_data(id_add)[0] == maildir_data(id_del)[0]
          updated.push [ id_del, id_add ]
          add_to_delete.push id_add
          del_to_delete.push id_del
        end
      end
    end
    added -= add_to_delete
    deleted -= del_to_delete
    debug "#{added.size} added, #{deleted.size} deleted, #{updated.size} updated"

    added.each_with_index do |id,i|
      yield :add,
      :info => File.join(d,id),
      :labels => @labels + maildir_labels(id) + [:inbox],
      :progress => i.to_f/(added.size+deleted.size)
    end

    deleted.each_with_index do |id,i|
      yield :delete,
      :info => File.join(d,id),
      :progress => (i.to_f+added.size)/(added.size+deleted.size)
    end

    # TODO: Fix this
    updated.each do |id|
      yield :update,
         :old_info => id[0],
         :new_info => id[1],
         :labels => @labels + maildir_labels(id[1]),
         :progress => 0.0
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

  def valid? id
    File.exists? File.join(@dir, id)
  end

private

  def new_maildir_basefn
    Kernel::srand()
    "#{Time.now.to_i.to_s}.#{$$}#{Kernel.rand(1000000)}.#{MYHOSTNAME}"
  end

  def with_file_for id
    fn = File.join(@dir, id)
    begin
      File.open(fn, 'rb') { |f| yield f }
    rescue SystemCallError, IOError => e
      raise FatalSourceError, "Problem reading file for id #{id.inspect}: #{fn.inspect}: #{e.message}."
    end
  end

  def maildir_data id
    id = File.basename id
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
