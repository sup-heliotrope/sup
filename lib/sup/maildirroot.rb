require 'uri'
require 'set'

module Redwood

# A Maildir Root source using each source as a label. Adding or deleting a
# a label in Sup means removing or copying a message to the label folders.
#
# Deleting a message in Sup means removing a message from all folders.

class MaildirRoot < Source
  include SerializeLabelsNicely
  MYHOSTNAME = Socket.gethostname

  ## remind me never to use inheritance again.
  yaml_properties :uri, :usual, :archived, :id, :labels, :syncback
  def initialize uri, usual=true, archived=false, id=nil, labels=[], syncback=false
    super uri, usual, archived, id
    @expanded_uri = Source.expand_filesystem_uri(uri)
    @syncable = true
    @syncback = syncback
    uri = URI(@expanded_uri)

    raise ArgumentError, "not a maildirroot URI" unless uri.scheme == "maildirroot"
    raise ArgumentError, "maildirroot URI cannot have a host: #{uri.host}" if uri.host
    raise ArgumentError, "maildirroot URI must have a path component" unless uri.path

    @root   = uri.path
    @labels = Set.new(labels || [])
    @mutex  = Mutex.new


    @inbox_folder   = 'inbox'
    @sent_folder    = 'sent'
    @drafts_folder  = 'drafts'
    @spam_folder    = 'spam'
    @trash_folder   = 'trash'
    @archive_folder = 'archive' # messages with no label should be here

    @all_special_folders = [@inbox_folder, @sent_folder, @drafts_folder,
                            @spam_folder, @trash_folder, @archive_folder]

    debug "setting up maildir subs.."
    @archive = MaildirSub.new self, @root, @archive_folder, :archive
    @inbox   = MaildirSub.new self, @root, @inbox_folder,   :inbox
    @sent    = MaildirSub.new self, @root, @sent_folder,    :sent
    @drafts  = MaildirSub.new self, @root, @drafts_folder,  :draft
    @spam    = MaildirSub.new self, @root, @spam_folder,    :spam
    @trash   = MaildirSub.new self, @root, @trash_folder,   :deleted

    # scan for other non-special folders
    debug "setting up non-special folders.."
    @maildirs = []
    Dir.new(@root).entries.select { |e|
      File.directory? File.join(@root,e) and e != '.' and e != '..' and !@all_special_folders.member? e
    }.each { |d|
      @maildirs.push MaildirSub.new(self, @root, d, :generic)
    }
    debug "maildir subs setup done."

    @special_maildirs  = [@inbox, @sent, @drafts, @spam, @trash]
    @extended_maildirs = @special_maildirs + @maildirs

    @all_maildirs = [@archive] + @extended_maildirs

    debug "all maildirs: #{@all_maildirs.inspect}"

  end

  # A class representing one maildir (label) in the maildir root
  class MaildirSub
    attr_reader :type, :maildirroot, :dir, :label, :basedir

    def initialize maildirroot, root, dir, type=:generic
      @maildirroot = maildirroot
      @root   = root
      @dir    = File.join(root, dir)
      @basedir = File.basename dir
      @type   = type
      # todo: shellwords.escape so that weird labels can have
      #       a disk representation.
      @label  = (@type == :generic) ? dir : @type.to_sym

      debug "maildirsub set up, type: #{@type}, label: #{@label}"
      @ctimes = { 'cur' => Time.at(0), 'new' => Time.at(0) }

      @mutex  = Mutex.new
    end

    def to_s
      "MaildirSub (#{@label})"
    end

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

    def new_maildir_basefn
      Kernel::srand()
      "#{Time.now.to_i.to_s}.#{$$}#{Kernel.rand(1000000)}.#{MYHOSTNAME}"
    end

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

        old_ids = benchmark(:maildirroot_read_index) { Enumerator.new(Index.instance, :each_source_info, @maildirroot.id, "#{@label.to_s}/#{d}/").to_a }

        new_ids = benchmark(:maildirroot_read_dir) { Dir.glob("#{subdir}/*").map { |x| File.join(@label.to_s,File.join(d,File.basename(x))) }.sort }
        added += new_ids - old_ids
        deleted += old_ids - new_ids
        debug "#{old_ids.size} in index, #{new_ids.size} in filesystem"
      end

      ## find updated mails by checking if an id is in both added and
      ## deleted arrays, meaning that its flags changed or that it has
      ## been moved, these ids need to be removed from added and deleted
      add_to_delete = del_to_delete = []
      map = Hash.new { |hash, key| hash[key] = [] }
      deleted.each do |id_del|
          map[maildir_data(id_del)[0]].push id_del
      end
      added.each do |id_add|
          map[maildir_data(id_add)[0]].each do |id_del|
            updated.push [ id_del, id_add ]
            add_to_delete.push id_add
            del_to_delete.push id_del
          end
      end
      added -= add_to_delete
      deleted -= del_to_delete
      debug "#{added.size} added, #{deleted.size} deleted, #{updated.size} updated"
      total_size = added.size + deleted.size + updated.size

      added.each_with_index do |id,i|
        yield :add,
        :info => id,
        :labels => @maildirroot.labels + maildir_labels(id) + (type == :archive ? [] : [@label.to_sym]),
        :progress => i.to_f/total_size
      end

      deleted.each_with_index do |id,i|
        if type == :archive
          yield :delete,
          :info => id,
          :progress => (i.to_f+added.size)/total_size
        else
          yield :delete,
            :old_info => id,
            :progress => (i.to_f+added.size)/total_size,
            :labels => @maildirroot.labels + maildir_labels(id[1]),
            :remove_labels => [@label.to_sym]
        end
      end

      updated.each_with_index do |id,i|
        yield :update,
        :old_info => id[0],
        :new_info => id[1],
        :labels => @maildirroot.labels + maildir_labels(id[1]),
        :progress => (i.to_f+added.size+deleted.size)/total_size
      end
      nil
    end

    def labels? id
      maildir_labels id
    end

    def maildir_data id
      id = File.basename id
      # Flags we recognize are DFPRST
      id =~ %r{^([^:]+):([12]),([A-Za-z]*)$}
      [($1 || id), ($2 || "2"), ($3 || "")]
    end

    def maildir_labels id
      (seen?(id) ? [] : [:unread]) +
        (trashed?(id) ?  [:deleted] : []) +
        (flagged?(id) ? [:starred] : []) +
        (passed?(id) ? [:forwarded] : []) +
        (replied?(id) ? [:replied] : []) +
        (draft?(id) ? [:draft] : [])
    end
    def draft? id; maildir_data(id)[2].include? "D"; end
    def flagged? id; maildir_data(id)[2].include? "F"; end
    def passed? id; maildir_data(id)[2].include? "P"; end
    def replied? id; maildir_data(id)[2].include? "R"; end
    def seen? id; maildir_data(id)[2].include? "S"; end
    def trashed? id; maildir_data(id)[2].include? "T"; end


    def maildir_mark_file orig_path, flags
      @mutex.synchronize do

        id = File.basename orig_path
        dd = File.dirname orig_path
        sub = File.basename dd
        orig_path = File.join sub, id

        Dir.chdir(@dir) do
          new_base = (flags.include?("S")) ? "cur" : "new"
          md_base, md_ver, md_flags = maildir_data orig_path

          return if md_flags == flags

          new_loc = File.join new_base, "#{md_base}:#{md_ver},#{flags}"
          orig_path = File.join @dir, orig_path
          new_path  = File.join @dir, new_loc
          tmp_path  = File.join @dir, "tmp", "#{md_base}:#{md_ver},#{flags}"

          File.link orig_path, tmp_path
          File.unlink orig_path
          File.link tmp_path, new_path
          File.unlink tmp_path

          new_loc
        end
      end
    end

    def maildir_reconcile_flags id, labels
        new_flags = Set.new( maildir_data(id)[2].each_char )

        # Set flags based on labels for the six flags we recognize
        if labels.member? :draft then new_flags.add?( "D" ) else new_flags.delete?( "D" ) end
        if labels.member? :starred then new_flags.add?( "F" ) else new_flags.delete?( "F" ) end
        if labels.member? :forwarded then new_flags.add?( "P" ) else new_flags.delete?( "P" ) end
        if labels.member? :replied then new_flags.add?( "R" ) else new_flags.delete?( "R" ) end
        if not labels.member? :unread then new_flags.add?( "S" ) else new_flags.delete?( "S" ) end
        if labels.member? :deleted or labels.member? :killed then new_flags.add?( "T" ) else new_flags.delete?( "T" ) end

        ## Flags must be stored in ASCII order according to Maildir
        ## documentation
        new_flags.to_a.sort.join
    end

    def store_message_from orig_path
      debug "#{self}: Storing message: #{orig_path}"

      orig_path = @maildirroot.get_real_id orig_path

      o = File.join @root, orig_path
      id = File.basename orig_path
      dd = File.dirname orig_path
      sub = File.basename dd

      new_path = File.join @dir, sub, id
      File.link o, new_path

      return File.join @label.to_s, sub, id
    end

    def remove_message path
      debug "#{self}: Removing message: #{path}"
      # not implemented yet
      Dir.chdir(@root) do
        File.unlink @maildirroot.get_real_id path
      end
    end
  end

  def valid? id
    return false if id == nil
    id = get_real_id id
    fn = File.join(@root, id)
    File.exists? fn
  end

  def file_path; @root end
  def self.suggest_labels_for path; [] end
  def is_source_for? uri; super || (uri == @expanded_uri); end

  # labels supported by the maildir file
  def supported_labels?
    # folders exist for (see below: folder_for_labels)
    [:draft, :starred, :forwarded, :replied, :unread, :deleted]
  end

  # special labels with corresponding maildir
  def folder_for_labels
    [:draft, :starred, :deleted]
  end

  # special sup labels that won't be synced
  def unsupported_labels
    [:attachment]
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

  # return id with label translated to real path of id
  def get_real_id id
    m  = maildirsub_from_info id
    id = id.gsub(/#{m.label.to_s}/, m.basedir)
  end

  def with_file_for id
    id = get_real_id id
    fn = File.join(@root, id)
    begin
      File.open(fn, 'rb') { |f| yield f }
    rescue SystemCallError, IOError => e
      raise FatalSourceError, "Problem reading file for id #{id.inspect}: #{fn.inspect}: #{e.message}."
    end
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

  # Polling strategy:
  #
  # - Poll messages from all maildirs
  # - Special folders correspond to special labels which might correspond
  #   to maildir flags. Will be fixed when message is synced or 'reconciled'.
  # - When a message is deleted: the label corresponding to its maildir is
  #   removed and the message is :update'd back to Poll, a array of
  #   :remove_labels specify which label should be removed.
  # - When a message is added: the corresponding label is added through :add.
  #   A new source is added which should now be in sync with the label.
  #
  # In sync_back:
  # - When a label is added the message is copied to the corresponding maildir
  # - When a label is deleted the message is deleted from the corresponding
  #   maildir.
  # - When a maildir flag (:unread, etc.) is changed the file name is changed
  #   on all sources(locations) using maildir_reconcile...
  def poll
    debug "polling @archive.."
    @all_maildirs.each do |maildir|
      debug "polling: #{maildir}.."

      maildir.poll do |sym,args|
        case sym
        when :add
          yield :add, args # easy..

        when :delete
          # remove this label from message and change to :update
          if maildir == @archive
            yield :delete, args
          else
            debug "Deleting: #{args[:new_info]}"
            yield :update, args
          end

        when :update
          # message should already have this label, but flags or dir have changed
          # re-check other labels if they are the same
          yield :update, args # should probably check if flags match other places as well
        end
      end
    end
  end

  def sync_back id, labels, msg
    if not @syncback
      debug "#{self.to_s}: syncback disabled for this source."
      return false
    end

    @poll_lock.synchronize do
      debug "maildirroot: syncing id: #{id}, labels: #{labels.inspect}"

      # todo: handle delete msgs
      # remove labels that do not have a a corresponding maildir
      l = labels - (supported_labels? - folder_for_labels) - unsupported_labels

      # local add: check if there are sources for all labels (will be done redundantly)
      label_sources = l.map { |l| maildirsub_from_label l }
      debug "label_sources: #{label_sources.inspect}"
      if label_sources.member? nil
        warn "Unknown label: Maildir creation not supported yet."
        raise NotImplementedError
      end

      existing_sources = msg.locations.select { |l| l.source.id == @id }.map { |l| maildirsub_from_info l.info }
      debug "existing_sources: #{existing_sources.inspect}"


      sources_to_add = label_sources - existing_sources
      debug "sources to add: #{sources_to_add}"

      fail "nil in sources_to_add" if sources_to_add.select { |s| s == nil }.any?

      # local del: check if a label exists for this source
      # if no label, copy to archive then remove
      sources_to_del = existing_sources - label_sources - [@archive]
      debug "sources to del: #{sources_to_del}"
      fail "nil in sources_to_del" if sources_to_del.select { |s| s == nil }.any?

      if (existing_sources - sources_to_del + sources_to_add).empty?
        warn "message no longer has any source, copying to archive."
        sources_to_add.push @archive
      end

      dirty = false

      sources_to_add.each do |s|
        # copy message to maildir
        new_info = s.store_message_from id
        msg.locations.push Location.new(self, new_info)
        dirty = true
      end

      sources_to_del.each do |s|
        l = msg.locations.select { |l| l.source.id == @id and maildirsub_from_info(l.info) == s }.first
        s.remove_message l.info
        msg.locations.delete Location.new(self, l.info)
        dirty = true
      end

      debug "msg.locations: #{msg.locations.inspect}"
      msg.locations.select { |l| l.source.id = @id }.each do |l|
        s = maildirsub_from_info (l.info)
        debug "checking maildir flags for: #{s}"

        # check maildir flags
        flags = s.maildir_reconcile_flags l.info, labels

        # mark file
        new_loc = s.maildir_mark_file l.info, flags
        if new_loc
          msg.locations.delete Location.new(self, l.info)
          msg.locations.push   Location.new(self, File.join(s.label.to_s, new_loc))
        end

        dirty = true
      end

      if dirty
        debug "maildirroot: syncing message: #{msg.id}"
        Index.sync_message msg, false, false
      end

      return false # don't return new info, locations have been taken care of..
    end
  end

  def labels; @labels; end

private
  def maildirsub_from_info info
    this_label = info
    while (File.dirname this_label) != '.'
      this_label = File.dirname this_label
    end

    this_label = this_label.to_sym
    return maildirsub_from_label this_label
  end

  def maildirsub_from_label label
    return @all_maildirs.select { |m| m.label.to_sym == label.to_sym }.first || nil
  end
end
end
