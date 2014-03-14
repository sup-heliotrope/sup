require 'uri'
require 'set'

module Redwood

# A Maildir Root source using each sub maildir as a label. Adding or deleting
# a label in Sup means copying to or removing a message in the corresponding
# maildir folder.
#
# All sub-folders will be added as a location to the message in the index, so
# that syncing the message back is a matter of updating the locations to match
# the labels of the message.
#
# Special labels that have corresponding folders (inbox, drafts, etc) are mapped
# as well. Special sup labels like :attachment are ignored. The maildir files
# are synced based on the file flag as in the regular maildir-syncback source.
#
# Where maildir flags and special folders overlap they are both synced. When a
# message is synced it is always added to archive if it is not already there.
#
# Files are copied using File.safe_link which means that they should not take
# any extra space on disk if your file system and platform supports hard
# links. When a file is removed from all labels it is copied
# to the archive folder unless it is already there.
#
# Deleted files are copied to the trash/:deleted special folder, a separate
# sync-back script should be used to delete messages with this label from
# _all_ the label-folders it exists in. Un-deleting a :deleted message works
# because it is still stored in all the other label-folders. The sync-back
# approach resembles the existing solution for mbox sources.
#
##  Warning on changing the sync_back flag:
#
#   Syncback is disabled by default. Changes you make to the Sup index (reading,
#   labeling, etc) might be lost when the remote message state changes. Local
#   existing changes are not propagated when the syncback flag is enabled, a
#   separate script should be run/made for updating/merging the
#   sup index -> maildir. But a clear merge strategy needs to be made
#   since changes might have been made on both sides (local and remote).
#
#   Consequently: This source does not work very well with the syncback flag
#   disabled and remote changes being made.

class MaildirRoot < Source
  include SerializeLabelsNicely

  ## remind me never to use inheritance again.
  yaml_properties :uri, :usual, :archived, :id, :labels, :sync_back,
                  :confirm_enable_experimental, :maildir_creation_allowed,
                  :inbox_folder,
                  :sent_folder, :drafts_folder, :spam_folder,
                  :trash_folder, :archive_folder
  def initialize uri, usual=true, archived=false, id=nil, labels=[],
                 sync_back=false, confirm_enable_experimental = false,
                 maildir_creation_allowed = false,
                 inbox_folder = 'inbox', sent_folder = 'sent',
                 drafts_folder = 'drafts', spam_folder = 'spam',
                 trash_folder = 'trash', archive_folder = 'archive'

    super uri, usual, archived, id
    @expanded_uri = Source.expand_filesystem_uri(uri)
    @syncable = true
    @sync_back = sync_back
    # do not sync by default if not specified
    @sync_back = false if @sync_back.nil?

    @confirm_enable_experimental = confirm_enable_experimental
    @maildir_creation_allowed = maildir_creation_allowed
    uri = URI(@expanded_uri)

    raise ArgumentError, "not a maildirroot URI" unless uri.scheme == "maildirroot"
    raise ArgumentError, "maildirroot URI cannot have a host: #{uri.host}" if uri.host
    raise ArgumentError, "maildirroot URI must have a path component" unless uri.path

    @root   = uri.path
    @labels = Set.new(labels || [])

    debug "#{self.to_s}: setting up maildirroot.."


    # special labels map to maildirs on disk
    @inbox_folder   = inbox_folder
    @sent_folder    = sent_folder
    @drafts_folder  = drafts_folder
    @spam_folder    = spam_folder
    @trash_folder   = trash_folder
    @archive_folder = archive_folder # messages with no label

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
    debug "setting up generic folders.."
    @maildirs = []
    Dir.new(@root).entries.select { |e|
      File.directory? File.join(@root,e) and e != '.' and e != '..' and !@all_special_folders.member? e
    }.each { |d|
      @maildirs.push MaildirSub.new(self, @root, d, :generic)
    }

    @special_maildirs  = [@inbox, @sent, @drafts, @spam, @trash]
    @extended_maildirs = @special_maildirs + @maildirs
    @all_maildirs      = [@archive] + @extended_maildirs
  end

  # A class representing one maildir (label) in the maildir root
  class MaildirSub
    MYHOSTNAME = Socket.gethostname

    attr_reader :type, :maildirroot, :dir, :label, :basedir

    def initialize maildirroot, root, dir, type=:generic
      @maildirroot = maildirroot
      @root   = root
      @dir    = File.join(root, dir)
      @basedir = File.basename dir
      @type   = type
      # todo: shellwords.escape so that weird labels can have
      #       a disk representation.
      @label  = (@type == :generic) ? dir.to_sym : @type.to_sym

      # todo: some folders in the gmail case are synced remotely
      #       automatically. specifically the 'starred' where it
      #       suffices to add the 'F' flag to the maildir file.

      debug "maildirsub set up, type: #{@type}, label: #{@label}"
      @ctimes = { 'cur' => Time.at(0), 'new' => Time.at(0) }

      @mutex  = Mutex.new

      # check if maildir is valid
      warn "#{self.to_s}: invalid maildir directory: #{@dir}, does there exist a maildir directory for the label: #{basedir}?" if not valid_maildir?
    end

    def to_s
      "MaildirSub (#{@label})"
    end

    def valid_maildir?
      File.directory?(@dir) &&
        File.directory?(File.join(@dir, 'cur')) &&
        File.directory?(File.join(@dir, 'new')) &&
        File.directory?(File.join(@dir, 'tmp'))
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

            File.safe_link tmp_path, new_path
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

        old_ids = benchmark(:maildirsub_read_index) { Enumerator.new(Index.instance, :each_source_info, @maildirroot.id, File.join(@label.to_s,d,'/')).to_a }

        new_ids = benchmark(:maildirsub_read_dir) { Dir.glob("#{subdir}/*").map { |x| File.join(@label.to_s, d, File.basename(x)) }.sort }

        #debug "old_ids: #{old_ids.inspect}"
        #debug "new_ids: #{new_ids.inspect}"

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
          # delete archive-location from msg without further ado, since this
          # means 'no labels' in sup/maildir language. and possibly a
          # remote delete.
          yield :delete,
          :info => id,
          :progress => (i.to_f+added.size)/total_size
        else
          # will be changed to :update in maildirroot
          # labels in :remove_labels will be removed along with
          # the old_info location. since no new new_info is provided
          # the location will not be replaced.
          yield :delete,
            :old_info => id,
            :progress => (i.to_f+added.size)/total_size,
            :labels => @maildirroot.labels + maildir_labels(id),
            :remove_labels => [@label.to_sym]
        end
      end

      updated.each_with_index do |id,i|
        yield :update,
        :old_info => id[0],
        :new_info => id[1],
        :labels =>   @maildirroot.labels + maildir_labels(id[1]),
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

          new_loc =   File.join new_base, "#{md_base}:#{md_ver},#{flags}"
          orig_path = File.join @dir, orig_path
          new_path  = File.join @dir, new_loc
          tmp_path  = File.join @dir, "tmp", "#{md_base}:#{md_ver},#{flags}"

          File.safe_link orig_path, tmp_path
          File.unlink orig_path
          File.safe_link tmp_path, new_path
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

    def store_message_from orig_path, msg
      debug "#{self}: Storing message: #{orig_path}"

      orig_path = @maildirroot.get_real_id orig_path

      o   = File.join @root, orig_path
      id  = File.basename orig_path
      dd  = File.dirname orig_path
      sub = File.basename dd

      new_flags = Set.new( maildir_data(id)[2].each_char )
      new_flags = new_flags.to_a.sort.join

      # create new id
      basefn    = "sup-#{Digest::MD5.hexdigest(msg.id)}"
      new_id    = basefn + ":2," + new_flags

      new_path = File.join @dir, sub, new_id

      if File.exist? new_path
        warn "#{self}: File already exists: #{new_path}"
      else
        File.safe_link o, new_path
      end

      return File.join @label.to_s, sub, new_id
    end

    def remove_message path
      debug "#{self}: Removing message: #{path}"
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

  # unsupported special sup labels that won't be synced
  def unsupported_labels
    LabelManager::RESERVED_LABELS - supported_labels? - @special_maildirs.map { |m| m.label }
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
    id = id.gsub(/^#{m.label.to_s}/, m.basedir)
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

  def check_enable_experimental
    if not @confirm_enable_experimental
      fail "This MaildirRoot source (#{self.to_s}) is EXPERIMENTAL. It might chew, hide or altogether totally delete your email. Forever. If you really are as adventurous as you claim to be please continue bravely forth and set 'confirm_enable_experimental' to 'true' as well as 'sync_back' to 'true' for this source in 'sources.yaml' in the Sup base directory. Otherwise; delete this source from your 'sources.yaml'."
    end
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
    check_enable_experimental

    benchmark (:maildirroot_pool) do
      added = []
      deleted = []
      updated = []

      @all_maildirs.each do |maildir|
        debug "polling: #{maildir}.."

        maildir.poll do |sym,args|
          case sym
          when :add
            # remote add: new label or new message in archive
            added.push args

          when :delete
            # remote del: remove label or message deleted
            # remove this label from message and change to :update
            if maildir == @archive
              deleted.push args
            else
              debug "maildirroot: pool: deleting: #{args[:old_info]}"
              updated.push args
            end

          when :update
            # remote: changed state on message
            # message should already have this label, but flags or dir have changed
            # re-check other labels if they are the same
            updated.push args
          end
        end
      end

      # now yield for all sources in right order
      added.each do |args|
        yield :add, args
      end
      updated.each do |args|
        yield :update, args
      end
      deleted.each do |args|
        yield :delete, args
      end
    end
  end

  # sync back will be called on one of the sub-locations (maildirsubs),
  # but we will sync all locations of the message. sync_back should therefore
  # only be called once for all the sub-locations of the maildirroot.
  def sync_back id, labels, msg
    check_enable_experimental

    if not @sync_back
      debug "#{self.to_s}: sync_back disabled for this source."
      return false
    end

    # ensure message is in @archive maildirsub
    msg = ensure_in_archive msg

    synchronize do
      debug "maildirroot: syncing id: #{id}, labels: #{labels.inspect}"

      dirty = false

      # remove labels that do not have a corresponding maildir
      l = labels - (supported_labels? - folder_for_labels) - unsupported_labels

      # local add: check if there are sources for all labels
      label_sources = l.map do |l|
        m = maildirsub_from_label l
        if m.nil?
          if @maildir_creation_allowed
            debug "#{self.to_s}: Creating maildir for label: #{l.to_s}"

            new_dir = File.join @root, l.to_s

            Dir.mkdir new_dir
            Dir.mkdir File.join new_dir, 'cur'
            Dir.mkdir File.join new_dir, 'new'
            Dir.mkdir File.join new_dir, 'tmp'

            # setting up maildirsub
            m = MaildirSub.new self, @root, l.to_s, :generic
            @maildirs.push m
            @extended_maildirs.push m
            @all_maildirs.push m

          else
            warn "Unknown label: #{l.to_s}: Maildir creation not allowed on this source (#{self.to_s})."
          end
        end

        m # map
      end

      debug "label_sources: #{label_sources.inspect}"
      if label_sources.member? nil
        warn "#{self.to_s}: Unknown labels (missing maildir), skipping from sync."
        label_sources = label_sources.select { |l| not l.nil? }
      end

      my_locations = msg.locations.select { |l| l.source.id == @id }
      existing_sources = my_locations.map { |l| maildirsub_from_info l.info }

      debug "existing_sources: #{existing_sources.inspect}"

      # remote rename:
      # check existing_sources
      new_existing_sources = existing_sources.dup
      existing_sources.each_with_index do |m,i|
        if not valid? my_locations[i].info
          info = my_locations[i].info
          debug "#{m.to_s}: invalid location: #{info}, deleting location from message."

          new_existing_sources[i] = nil
          msg.locations.delete Location.new(self,info)

          # does a duplicate source exist
          if new_existing_sources.member? m
            debug "#{m.to_s}: another source exists for same folder."
          end

          dirty = true
        end
      end

      existing_sources = new_existing_sources.select { |m| not m.nil? }
      debug "new existing_sources: #{existing_sources.inspect}"

      sources_to_add = label_sources - existing_sources

      #if not existing_sources.member? @archive
        #debug "message not in archive, adding."
        #sources_to_add.push @archive
      #end

      debug "sources to add: #{sources_to_add}"

      fail "nil in sources_to_add" if sources_to_add.select { |s| s == nil }.any?

      # local del: check if a label exists for this source
      # if no label, copy to archive then remove
      sources_to_del = existing_sources - label_sources - [@archive]
      debug "sources to del: #{sources_to_del}"
      fail "nil in sources_to_del" if sources_to_del.select { |s| s == nil }.any?

      ## this can no longer happen because @archive is always added to
      ## sources_to_add
      #if (existing_sources - sources_to_del + sources_to_add).empty?
        #warn "message no longer has any source, copying to archive."
        #sources_to_add.push @archive
      #end

      sources_to_add.each do |s|
        # copy message to maildir
        new_info = s.store_message_from id, msg
        msg.locations.push Location.new(self, new_info)
        dirty = true
      end

      sources_to_del.each do |s|
        # remove message from maildir
        l = msg.locations.select { |l| l.source.id == @id and maildirsub_from_info(l.info) == s }.first
        s.remove_message l.info
        msg.locations.delete Location.new(self, l.info)
        dirty = true
      end

      debug "msg.locations: #{msg.locations.inspect}"
      msg.locations.select { |l| l.source.id == @id }.each do |l|
        # local: message changed state
        s = maildirsub_from_info (l.info)
        debug "checking maildir flags for: #{s}"

        # check maildir flags
        flags   = s.maildir_reconcile_flags l.info, labels

        # mark file
        new_loc = s.maildir_mark_file l.info, flags

        # update location
        if new_loc
          debug "message moved to: #{new_loc}"
          msg.locations.delete Location.new(self, l.info)
          msg.locations.push   Location.new(self, File.join(s.label.to_s, new_loc))

          dirty = true
        end
      end

      if dirty
        return msg.locations
      else
        # nothing changed
        return false
      end
    end
  end

  # check if message also has a location in the archive (it should
  # automatically be added to archive by GMail servers) if not, add to the
  # archive source.
  #
  # If the message is in :spam or :deleted it should not be added.
  def ensure_in_archive msg

    if msg.labels.member?(:spam) or msg.labels.member?(:deleted)
      debug "message in spam or trash, not checking whether it is in archive"
      return msg
    end

    check_enable_experimental

    if @sync_back
      fail "no valid archive maildir!" unless @archive.valid_maildir?

      synchronize do
        my_locations = msg.locations.select { |l| l.source.id == @id }
        existing_sources = my_locations.map { |l| maildirsub_from_info l.info }

        # testing existing @archive sources
        add = true
        existing_sources.each_with_index do |s,i|
          if s == @archive
            unless valid? my_locations[i].info
              # possibly issue during update:
              # - we add message to @archive
              # - offlineimap renames it
              # - we get an add, but not update? and think the existing location is invalid
              debug "archive location invalid: #{my_locations[i].info}, deleting.."
              msg.locations.delete my_locations[i]
            else
              debug "valid archive location existing."
              add = false
            end
          end
        end

        if add
          debug "no valid archive location present, adding."
          valid_locations = my_locations.select { |l| valid? l.info }
          unless valid_locations.empty?
            new_info = @archive.store_message_from valid_locations.first.info, msg
            msg.locations.push Location.new(self, new_info)
          else
            warn "no valid locations could be found, could not archive message!"
          end
        end

      end

      msg
    end
  end

  # check if several sources indicate label and let poll know
  # if we really want a :deleted message to indicate a label
  # to be removed
  def really_remove? m, label
    # the locations that remain in m are the final locations and
    # if any of them provide label, keep message.
    m.locations.select { |l| l.source.id == @id }.each do |l|
      s = maildirsub_from_info l.info
      debug "really_remove: testing location: #{label} towards #{s.to_s}"
      if s.label.to_sym == label.to_sym
        return false
      end
    end

    debug "really_remove: could not find other source for: #{label}, should be deleted."
    return true
  end

  # should the message really be deleted if no more locations
  # exist for the message
  def really_delete? m
    true
  end

  # relay to @sent
  def store_message date, from_email, &block
    check_enable_experimental

    @sent.store_message date, from_email do |f|
      yield f
    end
  end

  # todo: store drafts

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

  def dir_from_label label
    maildirsub_from_label(label).basedir
  end

end
end
