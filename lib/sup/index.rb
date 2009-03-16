## the index structure for redwood. interacts with ferret.

require 'fileutils'
require 'ferret'
require 'fastthread'

begin
  require 'chronic'
  $have_chronic = true
rescue LoadError => e
  Redwood::log "optional 'chronic' library not found (run 'gem install chronic' to install)"
  $have_chronic = false
end

module Redwood

class Index
  class LockError < StandardError
    def initialize h
      @h = h
    end

    def method_missing m; @h[m.to_s] end
  end

  include Singleton

  ## these two accessors should ONLY be used by single-threaded programs.
  ## otherwise you will have a naughty ferret on your hands.
  attr_reader :index
  alias ferret index

  def initialize dir=BASE_DIR
    @index_mutex = Monitor.new

    @dir = dir
    @sources = {}
    @sources_dirty = false
    @source_mutex = Monitor.new

    wsa = Ferret::Analysis::WhiteSpaceAnalyzer.new false
    sa = Ferret::Analysis::StandardAnalyzer.new [], true
    @analyzer = Ferret::Analysis::PerFieldAnalyzer.new wsa
    @analyzer[:body] = sa
    @analyzer[:subject] = sa
    @qparser ||= Ferret::QueryParser.new :default_field => :body, :analyzer => @analyzer, :or_default => false
    @lock = Lockfile.new lockfile, :retries => 0, :max_age => nil

    self.class.i_am_the_instance self
  end

  def lockfile; File.join @dir, "lock" end

  def lock
    Redwood::log "locking #{lockfile}..."
    begin
      @lock.lock
    rescue Lockfile::MaxTriesLockError
      raise LockError, @lock.lockinfo_on_disk
    end
  end

  def start_lock_update_thread
    @lock_update_thread = Redwood::reporting_thread("lock update") do
      while true
        sleep 30
        @lock.touch_yourself
      end
    end
  end

  def stop_lock_update_thread
    @lock_update_thread.kill if @lock_update_thread
    @lock_update_thread = nil
  end

  def possibly_pluralize number_of, kind
    "#{number_of} #{kind}" +
        if number_of == 1 then "" else "s" end
  end

  def fancy_lock_error_message_for e
    secs = (Time.now - e.mtime).to_i
    mins = secs / 60
    time =
      if mins == 0
        possibly_pluralize secs , "second"
      else
        possibly_pluralize mins, "minute"
      end

    <<EOS
Error: the sup index is locked by another process! User '#{e.user}' on
host '#{e.host}' is running #{e.pname} with pid #{e.pid}. The process was alive
as of #{time} ago.
EOS
  end

  def lock_or_die
    begin
      lock
    rescue LockError => e
      $stderr.puts fancy_lock_error_message_for(e)
      $stderr.puts <<EOS

You can wait for the process to finish, or, if it crashed and left a
stale lock file behind, you can manually delete #{@lock.path}.
EOS
      exit
    end
  end

  def unlock
    if @lock && @lock.locked?
      Redwood::log "unlocking #{lockfile}..."
      @lock.unlock
    end
  end

  def load
    load_sources
    load_index
  end

  def save
    Redwood::log "saving index and sources..."
    FileUtils.mkdir_p @dir unless File.exists? @dir
    save_sources
    save_index
  end

  def add_source source
    @source_mutex.synchronize do
      raise "duplicate source!" if @sources.include? source
      @sources_dirty = true
      max = @sources.max_of { |id, s| s.is_a?(DraftLoader) || s.is_a?(SentLoader) ? 0 : id }
      source.id ||= (max || 0) + 1
      ##source.id += 1 while @sources.member? source.id
      @sources[source.id] = source
    end
  end

  def sources
    ## favour the inbox by listing non-archived sources first
    @source_mutex.synchronize { @sources.values }.sort_by { |s| s.id }.partition { |s| !s.archived? }.flatten
  end

  def source_for uri; sources.find { |s| s.is_source_for? uri }; end
  def usual_sources; sources.find_all { |s| s.usual? }; end

  def load_index dir=File.join(@dir, "ferret")
    if File.exists? dir
      Redwood::log "loading index..."
      @index_mutex.synchronize do
        @index = Ferret::Index::Index.new(:path => dir, :analyzer => @analyzer)
        Redwood::log "loaded index of #{@index.size} messages"
      end
    else
      Redwood::log "creating index..."
      @index_mutex.synchronize do
        field_infos = Ferret::Index::FieldInfos.new :store => :yes
        field_infos.add_field :message_id, :index => :untokenized
        field_infos.add_field :source_id
        field_infos.add_field :source_info
        field_infos.add_field :date, :index => :untokenized
        field_infos.add_field :body
        field_infos.add_field :label
        field_infos.add_field :attachments
        field_infos.add_field :subject
        field_infos.add_field :from
        field_infos.add_field :to
        field_infos.add_field :refs
        field_infos.add_field :snippet, :index => :no, :term_vector => :no
        field_infos.create_index dir
        @index = Ferret::Index::Index.new(:path => dir, :analyzer => @analyzer)
      end
    end
  end

  ## Syncs the message to the index: deleting if it's already there,
  ## and adding either way. Index state will be determined by m.labels.
  ##
  ## docid and entry can be specified if they're already known.
  def sync_message m, docid=nil, entry=nil, opts={}
    docid, entry = load_entry_for_id m.id unless docid && entry

    raise "no source info for message #{m.id}" unless m.source && m.source_info
    @index_mutex.synchronize do
      raise "trying to delete non-corresponding entry #{docid} with index message-id #{@index[docid][:message_id].inspect} and parameter message id #{m.id.inspect}" if docid && @index[docid][:message_id] != m.id
    end

    source_id = 
      if m.source.is_a? Integer
        m.source
      else
        m.source.id or raise "unregistered source #{m.source} (id #{m.source.id.inspect})"
      end

    snippet = 
      if m.snippet_contains_encrypted_content? && $config[:discard_snippets_from_encrypted_messages]
        ""
      else
        m.snippet
      end

    ## write the new document to the index. if the entry already exists in the
    ## index, reuse it (which avoids having to reload the entry from the source,
    ## which can be quite expensive for e.g. large threads of IMAP actions.)
    ##
    ## exception: if the index entry belongs to an earlier version of the
    ## message, use everything from the new message instead, but union the
    ## flags. this allows messages sent to mailing lists to have their header
    ## updated and to have flags set properly.
    ##
    ## minor hack: messages in sources with lower ids have priority over
    ## messages in sources with higher ids. so messages in the inbox will
    ## override everyone, and messages in the sent box will be overridden
    ## by everyone else.
    ##
    ## written in this manner to support previous versions of the index which
    ## did not keep around the entry body. upgrading is thus seamless.
    entry ||= {}
    labels = m.labels.uniq # override because this is the new state, unless...

    ## if we are a later version of a message, ignore what's in the index,
    ## but merge in the labels.
    if entry[:source_id] && entry[:source_info] && entry[:label] &&
      ((entry[:source_id].to_i > source_id) || (entry[:source_info].to_i < m.source_info))
      labels = (entry[:label].split(/\s+/).map { |l| l.intern } + m.labels).uniq
      #Redwood::log "found updated version of message #{m.id}: #{m.subj}"
      #Redwood::log "previous version was at #{entry[:source_id].inspect}:#{entry[:source_info].inspect}, this version at #{source_id.inspect}:#{m.source_info.inspect}"
      #Redwood::log "merged labels are #{labels.inspect} (index #{entry[:label].inspect}, message #{m.labels.inspect})"
      entry = {}
    end

    ## if force_overwite is true, ignore what's in the index. this is used
    ## primarily by sup-sync to force index updates.
    entry = {} if opts[:force_overwrite]

    d = {
      :message_id => m.id,
      :source_id => source_id,
      :source_info => m.source_info,
      :date => (entry[:date] || m.date.to_indexable_s),
      :body => (entry[:body] || m.indexable_content),
      :snippet => snippet, # always override
      :label => labels.uniq.join(" "),
      :attachments => (entry[:attachments] || m.attachments.uniq.join(" ")),
      :from => (entry[:from] || (m.from ? m.from.indexable_content : "")),
      :to => (entry[:to] || (m.to + m.cc + m.bcc).map { |x| x.indexable_content }.join(" ")),
      :subject => (entry[:subject] || wrap_subj(Message.normalize_subj(m.subj))),
      :refs => (entry[:refs] || (m.refs + m.replytos).uniq.join(" ")),
    }

    @index_mutex.synchronize  do
      @index.delete docid if docid
      @index.add_document d
    end

    docid, entry = load_entry_for_id m.id
    ## this hasn't been triggered in a long time. TODO: decide whether it's still a problem.
    raise "just added message #{m.id.inspect} but couldn't find it in a search" unless docid
    true
  end

  def save_index fn=File.join(@dir, "ferret")
    # don't have to do anything, apparently
  end

  def contains_id? id
    @index_mutex.synchronize { @index.search(Ferret::Search::TermQuery.new(:message_id, id)).total_hits > 0 }
  end
  def contains? m; contains_id? m.id end
  def size; @index_mutex.synchronize { @index.size } end
  def empty?; size == 0 end

  ## you should probably not call this on a block that doesn't break
  ## rather quickly because the results can be very large.
  EACH_BY_DATE_NUM = 100
  def each_id_by_date opts={}
    return if empty? # otherwise ferret barfs ###TODO: remove this once my ferret patch is accepted
    query = build_query opts
    offset = 0
    while true
      limit = (opts[:limit])? [EACH_BY_DATE_NUM, opts[:limit] - offset].min : EACH_BY_DATE_NUM
      results = @index_mutex.synchronize { @index.search query, :sort => "date DESC", :limit => limit, :offset => offset }
      Redwood::log "got #{results.total_hits} results for query (offset #{offset}) #{query.inspect}"
      results.hits.each do |hit|
        yield @index_mutex.synchronize { @index[hit.doc][:message_id] }, lambda { build_message hit.doc }
      end
      break if opts[:limit] and offset >= opts[:limit] - limit
      break if offset >= results.total_hits - limit
      offset += limit
    end
  end

  def num_results_for opts={}
    return 0 if empty? # otherwise ferret barfs ###TODO: remove this once my ferret patch is accepted

    q = build_query opts
    @index_mutex.synchronize { @index.search(q, :limit => 1).total_hits }
  end

  ## yield all messages in the thread containing 'm' by repeatedly
  ## querying the index. yields pairs of message ids and
  ## message-building lambdas, so that building an unwanted message
  ## can be skipped in the block if desired.
  ##
  ## only two options, :limit and :skip_killed. if :skip_killed is
  ## true, stops loading any thread if a message with a :killed flag
  ## is found.
  SAME_SUBJECT_DATE_LIMIT = 7
  MAX_CLAUSES = 1000
  def each_message_in_thread_for m, opts={}
    #Redwood::log "Building thread for #{m.id}: #{m.subj}"
    messages = {}
    searched = {}
    num_queries = 0

    pending = [m.id]
    if $config[:thread_by_subject] # do subject queries
      date_min = m.date - (SAME_SUBJECT_DATE_LIMIT * 12 * 3600)
      date_max = m.date + (SAME_SUBJECT_DATE_LIMIT * 12 * 3600)

      q = Ferret::Search::BooleanQuery.new true
      sq = Ferret::Search::PhraseQuery.new(:subject)
      wrap_subj(Message.normalize_subj(m.subj)).split(/\s+/).each do |t|
        sq.add_term t
      end
      q.add_query sq, :must
      q.add_query Ferret::Search::RangeQuery.new(:date, :>= => date_min.to_indexable_s, :<= => date_max.to_indexable_s), :must

      q = build_query :qobj => q

      p1 = @index_mutex.synchronize { @index.search(q).hits.map { |hit| @index[hit.doc][:message_id] } }
      Redwood::log "found #{p1.size} results for subject query #{q}"

      p2 = @index_mutex.synchronize { @index.search(q.to_s, :limit => :all).hits.map { |hit| @index[hit.doc][:message_id] } }
      Redwood::log "found #{p2.size} results in string form"

      pending = (pending + p1 + p2).uniq
    end

    until pending.empty? || (opts[:limit] && messages.size >= opts[:limit])
      q = Ferret::Search::BooleanQuery.new true
      # this disappeared in newer ferrets... wtf.
      # q.max_clause_count = 2048

      lim = [MAX_CLAUSES / 2, pending.length].min
      pending[0 ... lim].each do |id|
        searched[id] = true
        q.add_query Ferret::Search::TermQuery.new(:message_id, id), :should
        q.add_query Ferret::Search::TermQuery.new(:refs, id), :should
      end
      pending = pending[lim .. -1]

      q = build_query :qobj => q

      num_queries += 1
      killed = false
      @index_mutex.synchronize do
        @index.search_each(q, :limit => :all) do |docid, score|
          break if opts[:limit] && messages.size >= opts[:limit]
          if @index[docid][:label].split(/\s+/).include?("killed") && opts[:skip_killed]
            killed = true
            break
          end
          mid = @index[docid][:message_id]
          unless messages.member?(mid)
            #Redwood::log "got #{mid} as a child of #{id}"
            messages[mid] ||= lambda { build_message docid }
            refs = @index[docid][:refs].split(" ")
            pending += refs.select { |id| !searched[id] }
          end
        end
      end
    end

    if killed
      Redwood::log "thread for #{m.id} is killed, ignoring"
      false
    else
      Redwood::log "ran #{num_queries} queries to build thread of #{messages.size + 1} messages for #{m.id}: #{m.subj}" if num_queries > 0
      messages.each { |mid, builder| yield mid, builder }
      true
    end
  end

  ## builds a message object from a ferret result
  def build_message docid
    @index_mutex.synchronize do
      doc = @index[docid]

      source = @source_mutex.synchronize { @sources[doc[:source_id].to_i] }
      raise "invalid source #{doc[:source_id]}" unless source

      #puts "building message #{doc[:message_id]} (#{source}##{doc[:source_info]})"

      fake_header = {
        "date" => Time.at(doc[:date].to_i),
        "subject" => unwrap_subj(doc[:subject]),
        "from" => doc[:from],
        "to" => doc[:to].split(/\s+/).join(", "), # reformat
        "message-id" => doc[:message_id],
        "references" => doc[:refs].split(/\s+/).map { |x| "<#{x}>" }.join(" "),
      }

      Message.new :source => source, :source_info => doc[:source_info].to_i,
                  :labels => doc[:label].split(" ").map { |s| s.intern },
                  :snippet => doc[:snippet], :header => fake_header
    end
  end

  def fresh_thread_id; @next_thread_id += 1; end
  def wrap_subj subj; "__START_SUBJECT__ #{subj} __END_SUBJECT__"; end
  def unwrap_subj subj; subj =~ /__START_SUBJECT__ (.*?) __END_SUBJECT__/ && $1; end

  def drop_entry docno; @index_mutex.synchronize { @index.delete docno } end

  def load_entry_for_id mid
    @index_mutex.synchronize do
      results = @index.search Ferret::Search::TermQuery.new(:message_id, mid)
      return if results.total_hits == 0
      docid = results.hits[0].doc
      entry = @index[docid]
      entry_dup = entry.fields.inject({}) { |h, f| h[f] = entry[f]; h }
      [docid, entry_dup]
    end
  end

  def load_contacts emails, h={}
    q = Ferret::Search::BooleanQuery.new true
    emails.each do |e|
      qq = Ferret::Search::BooleanQuery.new true
      qq.add_query Ferret::Search::TermQuery.new(:from, e), :should
      qq.add_query Ferret::Search::TermQuery.new(:to, e), :should
      q.add_query qq
    end
    q.add_query Ferret::Search::TermQuery.new(:label, "spam"), :must_not
    
    Redwood::log "contact search: #{q}"
    contacts = {}
    num = h[:num] || 20
    @index_mutex.synchronize do
      @index.search_each q, :sort => "date DESC", :limit => :all do |docid, score|
        break if contacts.size >= num
        #Redwood::log "got message #{docid} to: #{@index[docid][:to].inspect} and from: #{@index[docid][:from].inspect}"
        f = @index[docid][:from]
        t = @index[docid][:to]

        if AccountManager.is_account_email? f
          t.split(" ").each { |e| contacts[Person.from_address(e)] = true }
        else
          contacts[Person.from_address(f)] = true
        end
      end
    end

    contacts.keys.compact
  end

  def load_sources fn=Redwood::SOURCE_FN
    source_array = (Redwood::load_yaml_obj(fn) || []).map { |o| Recoverable.new o }
    @source_mutex.synchronize do
      @sources = Hash[*(source_array).map { |s| [s.id, s] }.flatten]
      @sources_dirty = false
    end
  end

  def has_any_from_source_with_label? source, label
    q = Ferret::Search::BooleanQuery.new
    q.add_query Ferret::Search::TermQuery.new("source_id", source.id.to_s), :must
    q.add_query Ferret::Search::TermQuery.new("label", label.to_s), :must
    @index_mutex.synchronize { @index.search(q, :limit => 1).total_hits > 0 }
  end

protected

  ## do any specialized parsing
  ## returns nil and flashes error message if parsing failed
  def parse_user_query_string s
    extraopts = {}

    subs = s.gsub(/\b(to|from):(\S+)\b/) do
      field, name = $1, $2
      if(p = ContactManager.contact_for(name))
        [field, p.email]
      elsif name == "me"
        [field, "(" + AccountManager.user_emails.join("||") + ")"]
      else
        [field, name]
      end.join(":")
    end

    ## if we see a label:deleted or a label:spam term anywhere in the query
    ## string, we set the extra load_spam or load_deleted options to true.
    ## bizarre? well, because the query allows arbitrary parenthesized boolean
    ## expressions, without fully parsing the query, we can't tell whether
    ## the user is explicitly directing us to search spam messages or not.
    ## e.g. if the string is -(-(-(-(-label:spam)))), does the user want to
    ## search spam messages or not?
    ##
    ## so, we rely on the fact that turning these extra options ON turns OFF
    ## the adding of "-label:deleted" or "-label:spam" terms at the very
    ## final stage of query processing. if the user wants to search spam
    ## messages, not adding that is the right thing; if he doesn't want to
    ## search spam messages, then not adding it won't have any effect.
    extraopts[:load_spam] = true if subs =~ /\blabel:spam\b/
    extraopts[:load_deleted] = true if subs =~ /\blabel:deleted\b/

    ## gmail style "is" operator
    subs = subs.gsub(/\b(is|has):(\S+)\b/) do
      field, label = $1, $2
      case label
      when "read"
        "-label:unread"
      when "spam"
        extraopts[:load_spam] = true
        "label:spam"
      when "deleted"
        extraopts[:load_deleted] = true
        "label:deleted"
      else
        "label:#{$2}"
      end
    end

    ## gmail style attachments "filename" and "filetype" searches
    subs = subs.gsub(/\b(filename|filetype):(\((.+?)\)\B|(\S+)\b)/) do
      field, name = $1, ($3 || $4)
      case field
      when "filename"
        Redwood::log "filename - translated #{field}:#{name} to attachments:(#{name.downcase})"
        "attachments:(#{name.downcase})"
      when "filetype"
        Redwood::log "filetype - translated #{field}:#{name} to attachments:(*.#{name.downcase})"
        "attachments:(*.#{name.downcase})"
      end
    end

    if $have_chronic
      chronic_failure = false
      subs = subs.gsub(/\b(before|on|in|during|after):(\((.+?)\)\B|(\S+)\b)/) do
        break if chronic_failure
        field, datestr = $1, ($3 || $4)
        realdate = Chronic.parse(datestr, :guess => false, :context => :none)
        if realdate
          case field
          when "after"
            Redwood::log "chronic: translated #{field}:#{datestr} to #{realdate.end}"
            "date:(>= #{sprintf "%012d", realdate.end.to_i})"
          when "before"
            Redwood::log "chronic: translated #{field}:#{datestr} to #{realdate.begin}"
            "date:(<= #{sprintf "%012d", realdate.begin.to_i})"
          else
            Redwood::log "chronic: translated #{field}:#{datestr} to #{realdate}"
            "date:(<= #{sprintf "%012d", realdate.end.to_i}) date:(>= #{sprintf "%012d", realdate.begin.to_i})"
          end
        else
          BufferManager.flash "Can't understand date #{datestr.inspect}!"
          chronic_failure = true
        end
      end
      subs = nil if chronic_failure
    end

    ## limit:42 restrict the search to 42 results
    subs = subs.gsub(/\blimit:(\S+)\b/) do
      lim = $1
      if lim =~ /^\d+$/
        extraopts[:limit] = lim.to_i
        ''
      else
        BufferManager.flash "Can't understand limit #{lim.inspect}!"
        subs = nil
      end
    end
    
    if subs
      [@qparser.parse(subs), extraopts]
    else
      nil
    end
  end

  def build_query opts
    query = Ferret::Search::BooleanQuery.new
    query.add_query opts[:qobj], :must if opts[:qobj]
    labels = ([opts[:label]] + (opts[:labels] || [])).compact
    labels.each { |t| query.add_query Ferret::Search::TermQuery.new("label", t.to_s), :must }
    if opts[:participants]
      q2 = Ferret::Search::BooleanQuery.new
      opts[:participants].each do |p|
        q2.add_query Ferret::Search::TermQuery.new("from", p.email), :should
        q2.add_query Ferret::Search::TermQuery.new("to", p.email), :should
      end
      query.add_query q2, :must
    end
        
    query.add_query Ferret::Search::TermQuery.new("label", "spam"), :must_not unless opts[:load_spam] || labels.include?(:spam)
    query.add_query Ferret::Search::TermQuery.new("label", "deleted"), :must_not unless opts[:load_deleted] || labels.include?(:deleted)
    query.add_query Ferret::Search::TermQuery.new("label", "killed"), :must_not if opts[:skip_killed]
    query
  end

  def save_sources fn=Redwood::SOURCE_FN
    @source_mutex.synchronize do
      if @sources_dirty || @sources.any? { |id, s| s.dirty? }
        bakfn = fn + ".bak"
        if File.exists? fn
          File.chmod 0600, fn
          FileUtils.mv fn, bakfn, :force => true unless File.exists?(bakfn) && File.size(fn) == 0
        end
        Redwood::save_yaml_obj sources.sort_by { |s| s.id.to_i }, fn, true
        File.chmod 0600, fn
      end
      @sources_dirty = false
    end
  end
end

end
