ENV["XAPIAN_FLUSH_THRESHOLD"] = "1000"

require 'xapian'
require 'set'
require 'fileutils'
require 'monitor'

begin
  require 'chronic'
  $have_chronic = true
rescue LoadError => e
  debug "No 'chronic' gem detected. Install it for date/time query restrictions."
  $have_chronic = false
end

if ([Xapian.major_version, Xapian.minor_version, Xapian.revision] <=> [1,2,1]) < 0
	fail "Xapian version 1.2.1 or higher required"
end

module Redwood

# This index implementation uses Xapian for searching and storage. It
# tends to be slightly faster than Ferret for indexing and significantly faster
# for searching due to precomputing thread membership.
class Index
  include InteractiveLock

  STEM_LANGUAGE = "english"
  INDEX_VERSION = '4'

  ## dates are converted to integers for xapian, and are used for document ids,
  ## so we must ensure they're reasonably valid. this typically only affect
  ## spam.
  MIN_DATE = Time.at 0
  MAX_DATE = Time.at(2**31-1)

  HookManager.register "custom-search", <<EOS
Executes before a string search is applied to the index,
returning a new search string.
Variables:
  subs: The string being searched.
EOS

  class LockError < StandardError
    def initialize h
      @h = h
    end

    def method_missing m; @h[m.to_s] end
  end

  include Singleton

  def initialize dir=BASE_DIR
    @dir = dir
    FileUtils.mkdir_p @dir
    @lock = Lockfile.new lockfile, :retries => 0, :max_age => nil
    @sync_worker = nil
    @sync_queue = Queue.new
    @index_mutex = Monitor.new
  end

  def lockfile; File.join @dir, "lock" end

  def lock
    debug "locking #{lockfile}..."
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

  def unlock
    if @lock && @lock.locked?
      debug "unlocking #{lockfile}..."
      @lock.unlock
    end
  end

  def load
    SourceManager.load_sources
    load_index
  end

  def save
    debug "saving index and sources..."
    FileUtils.mkdir_p @dir unless File.exists? @dir
    SourceManager.save_sources
    save_index
  end

  def load_index
    path = File.join(@dir, 'xapian')
    if File.exists? path
      @xapian = Xapian::WritableDatabase.new(path, Xapian::DB_OPEN)
      db_version = @xapian.get_metadata 'version'
      db_version = '0' if db_version.empty?
      if false
        info "Upgrading index format #{db_version} to #{INDEX_VERSION}"
        @xapian.set_metadata 'version', INDEX_VERSION
      elsif db_version != INDEX_VERSION
        fail "This Sup version expects a v#{INDEX_VERSION} index, but you have an existing v#{db_version} index. Please run sup-dump to save your labels, move #{path} out of the way, and run sup-sync --restore."
      end
    else
      @xapian = Xapian::WritableDatabase.new(path, Xapian::DB_CREATE)
      @xapian.set_metadata 'version', INDEX_VERSION
      @xapian.set_metadata 'rescue-version', '0'
    end
    @enquire = Xapian::Enquire.new @xapian
    @enquire.weighting_scheme = Xapian::BoolWeight.new
    @enquire.docid_order = Xapian::Enquire::ASCENDING
  end

  def add_message m; sync_message m, true end
  def update_message m; sync_message m, true end
  def update_message_state m; sync_message m, false end

  def save_index
    info "Flushing Xapian updates to disk. This may take a while..."
    @xapian.flush
  end

  def contains_id? id
    synchronize { find_docid(id) && true }
  end

  def contains? m; contains_id? m.id end

  def size
    synchronize { @xapian.doccount }
  end

  def empty?; size == 0 end

  ## Yields a message-id and message-building lambda for each
  ## message that matches the given query, in descending date order.
  ## You should probably not call this on a block that doesn't break
  ## rather quickly because the results can be very large.
  def each_id_by_date query={}
    each_id(query) { |id| yield id, lambda { build_message id } }
  end

  ## Return the number of matches for query in the index
  def num_results_for query={}
    xapian_query = build_xapian_query query
    matchset = run_query xapian_query, 0, 0, 100
    matchset.matches_estimated
  end

  ## yield all messages in the thread containing 'm' by repeatedly
  ## querying the index. yields pairs of message ids and
  ## message-building lambdas, so that building an unwanted message
  ## can be skipped in the block if desired.
  ##
  ## only two options, :limit and :skip_killed. if :skip_killed is
  ## true, stops loading any thread if a message with a :killed flag
  ## is found.
  def each_message_in_thread_for m, opts={}
    # TODO thread by subject
    return unless doc = find_doc(m.id)
    queue = doc.value(THREAD_VALUENO).split(',')
    msgids = [m.id]
    seen_threads = Set.new
    seen_messages = Set.new [m.id]
    while not queue.empty?
      thread_id = queue.pop
      next if seen_threads.member? thread_id
      return false if opts[:skip_killed] && thread_killed?(thread_id)
      seen_threads << thread_id
      docs = term_docids(mkterm(:thread, thread_id)).map { |x| @xapian.document x }
      docs.each do |doc|
        msgid = doc.value MSGID_VALUENO
        next if seen_messages.member? msgid
        msgids << msgid
        seen_messages << msgid
        queue.concat doc.value(THREAD_VALUENO).split(',')
      end
    end
    msgids.each { |id| yield id, lambda { build_message id } }
    true
  end

  ## Load message with the given message-id from the index
  def build_message id
    entry = synchronize { get_entry id }
    return unless entry

    locations = entry[:locations].map do |source_id,source_info|
      source = SourceManager[source_id]
      raise "invalid source #{source_id}" unless source
      Location.new source, source_info
    end

    m = Message.new :locations => locations,
                    :labels => entry[:labels],
                    :snippet => entry[:snippet]

    # Try to find person from contacts before falling back to
    # generating it from the address.
    mk_person = lambda { |x| Person.from_name_and_email(*x.reverse!) }
    entry[:from] = mk_person[entry[:from]]
    entry[:to].map!(&mk_person)
    entry[:cc].map!(&mk_person)
    entry[:bcc].map!(&mk_person)

    m.load_from_index! entry
    m
  end

  ## Delete message with the given message-id from the index
  def delete id
    synchronize { @xapian.delete_document mkterm(:msgid, id) }
  end

  ## Given an array of email addresses, return an array of Person objects that
  ## have sent mail to or received mail from any of the given addresses.
  def load_contacts email_addresses, opts={}
    contacts = Set.new
    num = opts[:num] || 20
    each_id_by_date :participants => email_addresses do |id,b|
      break if contacts.size >= num
      m = b.call
      ([m.from]+m.to+m.cc+m.bcc).compact.each { |p| contacts << [p.name, p.email] }
    end
    contacts.to_a.compact[0...num].map { |n,e| Person.from_name_and_email n, e }
  end

  ## Yield each message-id matching query
  EACH_ID_PAGE = 100
  def each_id query={}
    offset = 0
    page = EACH_ID_PAGE

    xapian_query = build_xapian_query query
    while true
      ids = run_query_ids xapian_query, offset, (offset+page)
      ids.each { |id| yield id }
      break if ids.size < page
      offset += page
    end
  end

  ## Yield each message matching query
  def each_message query={}, &b
    each_id query do |id|
      yield build_message(id)
    end
  end

  # wrap all future changes inside a transaction so they're done atomically
  def begin_transaction
    synchronize { @xapian.begin_transaction }
  end

  # complete the transaction and write all previous changes to disk
  def commit_transaction
    synchronize { @xapian.commit_transaction }
  end

  # abort the transaction and revert all changes made since begin_transaction
  def cancel_transaction
    synchronize { @xapian.cancel_transaction }
  end

  ## xapian-compact takes too long, so this is a no-op
  ## until we think of something better
  def optimize
  end

  ## Return the id source of the source the message with the given message-id
  ## was synced from
  def source_for_id id
    synchronize { get_entry(id)[:source_id] }
  end

  ## Yields each tearm in the index that starts with prefix
  def each_prefixed_term prefix
    term = @xapian._dangerous_allterms_begin prefix
    lastTerm = @xapian._dangerous_allterms_end prefix
    until term.equals lastTerm
      yield term.term
      term.next
    end
    nil
  end

  ## Yields (in lexicographical order) the source infos of all locations from
  ## the given source with the given source_info prefix
  def each_source_info source_id, prefix='', &b
    prefix = mkterm :location, source_id, prefix
    each_prefixed_term prefix do |x|
      yield x[prefix.length..-1]
    end
  end

  class ParseError < StandardError; end

  ## parse a query string from the user. returns a query object
  ## that can be passed to any index method with a 'query'
  ## argument.
  ##
  ## raises a ParseError if something went wrong.
  def parse_query s
    query = {}

    subs = HookManager.run("custom-search", :subs => s) || s
    begin
      subs = SearchManager.expand subs
    rescue SearchManager::ExpansionError => e
      raise ParseError, e.message
    end
    subs = subs.gsub(/\b(to|from):(\S+)\b/) do
      field, value = $1, $2
      email_field, name_field = %w(email name).map { |x| "#{field}_#{x}" }
      if(p = ContactManager.contact_for(value))
        "#{email_field}:#{p.email}"
      elsif value == "me"
        '(' + AccountManager.user_emails.map { |e| "#{email_field}:#{e}" }.join(' OR ') + ')'
      else
        "(#{email_field}:#{value} OR #{name_field}:#{value})"
      end
    end

    ## gmail style "is" operator
    subs = subs.gsub(/\b(is|has):(\S+)\b/) do
      field, label = $1, $2
      case label
      when "read"
        "-label:unread"
      when "spam"
        query[:load_spam] = true
        "label:spam"
      when "deleted"
        query[:load_deleted] = true
        "label:deleted"
      else
        "label:#{$2}"
      end
    end

    ## labels are stored lower-case in the index
    subs = subs.gsub(/\blabel:(\S+)\b/) do
      label = $1
      "label:#{label.downcase}"
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
    query[:load_spam] = true if subs =~ /\blabel:spam\b/
    query[:load_deleted] = true if subs =~ /\blabel:deleted\b/
    query[:load_killed] = true if subs =~ /\blabel:killed\b/

    ## gmail style attachments "filename" and "filetype" searches
    subs = subs.gsub(/\b(filename|filetype):(\((.+?)\)\B|(\S+)\b)/) do
      field, name = $1, ($3 || $4)
      case field
      when "filename"
        debug "filename: translated #{field}:#{name} to attachment:\"#{name.downcase}\""
        "attachment:\"#{name.downcase}\""
      when "filetype"
        debug "filetype: translated #{field}:#{name} to attachment_extension:#{name.downcase}"
        "attachment_extension:#{name.downcase}"
      end
    end

    if $have_chronic
      lastdate = 2<<32 - 1
      firstdate = 0
      subs = subs.gsub(/\b(before|on|in|during|after):(\((.+?)\)\B|(\S+)\b)/) do
        field, datestr = $1, ($3 || $4)
        realdate = Chronic.parse datestr, :guess => false, :context => :past
        if realdate
          case field
          when "after"
            debug "chronic: translated #{field}:#{datestr} to #{realdate.end}"
            "date:#{realdate.end.to_i}..#{lastdate}"
          when "before"
            debug "chronic: translated #{field}:#{datestr} to #{realdate.begin}"
            "date:#{firstdate}..#{realdate.end.to_i}"
          else
            debug "chronic: translated #{field}:#{datestr} to #{realdate}"
            "date:#{realdate.begin.to_i}..#{realdate.end.to_i}"
          end
        else
          raise ParseError, "can't understand date #{datestr.inspect}"
        end
      end
    end

    ## limit:42 restrict the search to 42 results
    subs = subs.gsub(/\blimit:(\S+)\b/) do
      lim = $1
      if lim =~ /^\d+$/
        query[:limit] = lim.to_i
        ''
      else
        raise ParseError, "non-numeric limit #{lim.inspect}"
      end
    end

    debug "translated query: #{subs.inspect}"

    qp = Xapian::QueryParser.new
    qp.database = @xapian
    qp.stemmer = Xapian::Stem.new(STEM_LANGUAGE)
    qp.stemming_strategy = Xapian::QueryParser::STEM_SOME
    qp.default_op = Xapian::Query::OP_AND
    qp.add_valuerangeprocessor(Xapian::NumberValueRangeProcessor.new(DATE_VALUENO, 'date:', true))
    NORMAL_PREFIX.each { |k,info| info[:prefix].each { |v| qp.add_prefix k, v } }
    BOOLEAN_PREFIX.each { |k,info| info[:prefix].each { |v| qp.add_boolean_prefix k, v, info[:exclusive] } }

    begin
      xapian_query = qp.parse_query(subs, Xapian::QueryParser::FLAG_PHRASE|Xapian::QueryParser::FLAG_BOOLEAN|Xapian::QueryParser::FLAG_LOVEHATE|Xapian::QueryParser::FLAG_WILDCARD)
    rescue RuntimeError => e
      raise ParseError, "xapian query parser error: #{e}"
    end

    debug "parsed xapian query: #{xapian_query.description}"

    raise ParseError if xapian_query.nil? or xapian_query.empty?
    query[:qobj] = xapian_query
    query[:text] = s
    query
  end

  def save_thread t
    t.each_dirty_message do |m|
      if @sync_worker
        @sync_queue << m
      else
        update_message_state m
      end
      m.clear_dirty
    end
  end

  def start_sync_worker
    @sync_worker = Redwood::reporting_thread('index sync') { run_sync_worker }
  end

  def stop_sync_worker
    return unless worker = @sync_worker
    @sync_worker = nil
    @sync_queue << :die
    worker.join
  end

  def run_sync_worker
    while m = @sync_queue.deq
      return if m == :die
      update_message_state m
      # Necessary to keep Xapian calls from lagging the UI too much.
      sleep 0.03
    end
  end

  private

  # Stemmed
  NORMAL_PREFIX = {
    'subject' => {:prefix => 'S', :exclusive => false},
    'body' => {:prefix => 'B', :exclusive => false},
    'from_name' => {:prefix => 'FN', :exclusive => false},
    'to_name' => {:prefix => 'TN', :exclusive => false},
    'name' => {:prefix => %w(FN TN), :exclusive => false},
    'attachment' => {:prefix => 'A', :exclusive => false},
    'email_text' => {:prefix => 'E', :exclusive => false},
    '' => {:prefix => %w(S B FN TN A E), :exclusive => false},
  }

  # Unstemmed
  BOOLEAN_PREFIX = {
    'type' => {:prefix => 'K', :exclusive => true},
    'from_email' => {:prefix => 'FE', :exclusive => false},
    'to_email' => {:prefix => 'TE', :exclusive => false},
    'email' => {:prefix => %w(FE TE), :exclusive => false},
    'date' => {:prefix => 'D', :exclusive => true},
    'label' => {:prefix => 'L', :exclusive => false},
    'source_id' => {:prefix => 'I', :exclusive => true},
    'attachment_extension' => {:prefix => 'O', :exclusive => false},
    'msgid' => {:prefix => 'Q', :exclusive => true},
    'id' => {:prefix => 'Q', :exclusive => true},
    'thread' => {:prefix => 'H', :exclusive => false},
    'ref' => {:prefix => 'R', :exclusive => false},
    'location' => {:prefix => 'J', :exclusive => false},
  }

  PREFIX = NORMAL_PREFIX.merge BOOLEAN_PREFIX

  MSGID_VALUENO = 0
  THREAD_VALUENO = 1
  DATE_VALUENO = 2

  MAX_TERM_LENGTH = 245

  # Xapian can very efficiently sort in ascending docid order. Sup always wants
  # to sort by descending date, so this method maps between them. In order to
  # handle multiple messages per second, we use a logistic curve centered
  # around MIDDLE_DATE so that the slope (docid/s) is greatest in this time
  # period. A docid collision is not an error - the code will pick the next
  # smallest unused one.
  DOCID_SCALE = 2.0**32
  TIME_SCALE = 2.0**27
  MIDDLE_DATE = Time.gm(2011)
  def assign_docid m, truncated_date
    t = (truncated_date.to_i - MIDDLE_DATE.to_i).to_f
    docid = (DOCID_SCALE - DOCID_SCALE/(Math::E**(-(t/TIME_SCALE)) + 1)).to_i
    while docid > 0 and docid_exists? docid
      docid -= 1
    end
    docid > 0 ? docid : nil
  end

  # XXX is there a better way?
  def docid_exists? docid
    begin
      @xapian.doclength docid
      true
    rescue RuntimeError #Xapian::DocNotFoundError
      raise unless $!.message =~ /DocNotFoundError/
      false
    end
  end

  def term_docids term
    @xapian.postlist(term).map { |x| x.docid }
  end

  def find_docid id
    docids = term_docids(mkterm(:msgid,id))
    fail unless docids.size <= 1
    docids.first
  end

  def find_doc id
    return unless docid = find_docid(id)
    @xapian.document docid
  end

  def get_id docid
    return unless doc = @xapian.document(docid)
    doc.value MSGID_VALUENO
  end

  def get_entry id
    return unless doc = find_doc(id)
    doc.entry
  end

  def thread_killed? thread_id
    not run_query(Q.new(Q::OP_AND, mkterm(:thread, thread_id), mkterm(:label, :Killed)), 0, 1).empty?
  end

  def synchronize &b
    @index_mutex.synchronize &b
  end

  def run_query xapian_query, offset, limit, checkatleast=0
    synchronize do
      @enquire.query = xapian_query
      @enquire.mset(offset, limit-offset, checkatleast)
    end
  end

  def run_query_ids xapian_query, offset, limit
    matchset = run_query xapian_query, offset, limit
    matchset.matches.map { |r| r.document.value MSGID_VALUENO }
  end

  Q = Xapian::Query
  def build_xapian_query opts
    labels = ([opts[:label]] + (opts[:labels] || [])).compact
    neglabels = [:spam, :deleted, :killed].reject { |l| (labels.include? l) || opts.member?("load_#{l}".intern) }
    pos_terms, neg_terms = [], []

    pos_terms << mkterm(:type, 'mail')
    pos_terms.concat(labels.map { |l| mkterm(:label,l) })
    pos_terms << opts[:qobj] if opts[:qobj]
    pos_terms << mkterm(:source_id, opts[:source_id]) if opts[:source_id]
    pos_terms << mkterm(:location, *opts[:location]) if opts[:location]

    if opts[:participants]
      participant_terms = opts[:participants].map { |p| [:from,:to].map { |d| mkterm(:email, d, (Redwood::Person === p) ? p.email : p) } }.flatten
      pos_terms << Q.new(Q::OP_OR, participant_terms)
    end

    neg_terms.concat(neglabels.map { |l| mkterm(:label,l) })

    pos_query = Q.new(Q::OP_AND, pos_terms)
    neg_query = Q.new(Q::OP_OR, neg_terms)

    if neg_query.empty?
      pos_query
    else
      Q.new(Q::OP_AND_NOT, [pos_query, neg_query])
    end
  end

  def sync_message m, overwrite
    doc = synchronize { find_doc(m.id) }
    existed = doc != nil
    doc ||= Xapian::Document.new
    do_index_static = overwrite || !existed
    old_entry = !do_index_static && doc.entry
    snippet = do_index_static ? m.snippet : old_entry[:snippet]

    entry = {
      :message_id => m.id,
      :locations => m.locations.map { |x| [x.source.id, x.info] },
      :date => truncate_date(m.date),
      :snippet => snippet,
      :labels => m.labels.to_a,
      :from => [m.from.email, m.from.name],
      :to => m.to.map { |p| [p.email, p.name] },
      :cc => m.cc.map { |p| [p.email, p.name] },
      :bcc => m.bcc.map { |p| [p.email, p.name] },
      :subject => m.subj,
      :refs => m.refs.to_a,
      :replytos => m.replytos.to_a,
    }

    if do_index_static
      doc.clear_terms
      doc.clear_values
      index_message_static m, doc, entry
    end

    index_message_locations doc, entry, old_entry
    index_message_threading doc, entry, old_entry
    index_message_labels doc, entry[:labels], (do_index_static ? [] : old_entry[:labels])
    doc.entry = entry

    synchronize do
      unless docid = existed ? doc.docid : assign_docid(m, truncate_date(m.date))
        # Could be triggered by spam
        warn "docid underflow, dropping #{m.id.inspect}"
        return
      end
      @xapian.replace_document docid, doc
    end

    m.labels.each { |l| LabelManager << l }
    true
  end

  ## Index content that can't be changed by the user
  def index_message_static m, doc, entry
    # Person names are indexed with several prefixes
    person_termer = lambda do |d|
      lambda do |p|
        doc.index_text p.name, PREFIX["#{d}_name"][:prefix] if p.name
        doc.index_text p.email, PREFIX['email_text'][:prefix]
        doc.add_term mkterm(:email, d, p.email)
      end
    end

    person_termer[:from][m.from] if m.from
    (m.to+m.cc+m.bcc).each(&(person_termer[:to]))

    # Full text search content
    subject_text = m.indexable_subject
    body_text = m.indexable_body
    doc.index_text subject_text, PREFIX['subject'][:prefix]
    doc.index_text body_text, PREFIX['body'][:prefix]
    m.attachments.each { |a| doc.index_text a, PREFIX['attachment'][:prefix] }

    # Miscellaneous terms
    doc.add_term mkterm(:date, m.date) if m.date
    doc.add_term mkterm(:type, 'mail')
    doc.add_term mkterm(:msgid, m.id)
    m.attachments.each do |a|
      a =~ /\.(\w+)$/ or next
      doc.add_term mkterm(:attachment_extension, $1)
    end

    # Date value for range queries
    date_value = begin
      Xapian.sortable_serialise m.date.to_i
    rescue TypeError
      Xapian.sortable_serialise 0
    end

    doc.add_value MSGID_VALUENO, m.id
    doc.add_value DATE_VALUENO, date_value
  end

  def index_message_locations doc, entry, old_entry
    old_entry[:locations].map { |x| x[0] }.uniq.each { |x| doc.remove_term mkterm(:source_id, x) } if old_entry
    entry[:locations].map { |x| x[0] }.uniq.each { |x| doc.add_term mkterm(:source_id, x) }
    old_entry[:locations].each { |x| (doc.remove_term mkterm(:location, *x) rescue nil) } if old_entry
    entry[:locations].each { |x| doc.add_term mkterm(:location, *x) }
  end

  def index_message_labels doc, new_labels, old_labels
    return if new_labels == old_labels
    added = new_labels.to_a - old_labels.to_a
    removed = old_labels.to_a - new_labels.to_a
    added.each { |t| doc.add_term mkterm(:label,t) }
    removed.each { |t| doc.remove_term mkterm(:label,t) }
  end

  ## Assign a set of thread ids to the document. This is a hybrid of the runtime
  ## search done by the Ferret index and the index-time union done by previous
  ## versions of the Xapian index. We first find the thread ids of all messages
  ## with a reference to or from us. If that set is empty, we use our own
  ## message id. Otherwise, we use all the thread ids we previously found. In
  ## the common case there's only one member in that set, but if we're the
  ## missing link between multiple previously unrelated threads we can have
  ## more. XapianIndex#each_message_in_thread_for follows the thread ids when
  ## searching so the user sees a single unified thread.
  def index_message_threading doc, entry, old_entry
    return if old_entry && (entry[:refs] == old_entry[:refs]) && (entry[:replytos] == old_entry[:replytos])
    children = term_docids(mkterm(:ref, entry[:message_id])).map { |docid| @xapian.document docid }
    parent_ids = entry[:refs] + entry[:replytos]
    parents = parent_ids.map { |id| find_doc id }.compact
    thread_members = SavingHash.new { [] }
    (children + parents).each do |doc2|
      thread_ids = doc2.value(THREAD_VALUENO).split ','
      thread_ids.each { |thread_id| thread_members[thread_id] << doc2 }
    end
    thread_ids = thread_members.empty? ? [entry[:message_id]] : thread_members.keys
    thread_ids.each { |thread_id| doc.add_term mkterm(:thread, thread_id) }
    parent_ids.each { |ref| doc.add_term mkterm(:ref, ref) }
    doc.add_value THREAD_VALUENO, (thread_ids * ',')
  end

  def truncate_date date
    if date < MIN_DATE
      debug "warning: adjusting too-low date #{date} for indexing"
      MIN_DATE
    elsif date > MAX_DATE
      debug "warning: adjusting too-high date #{date} for indexing"
      MAX_DATE
    else
      date
    end
  end

  # Construct a Xapian term
  def mkterm type, *args
    case type
    when :label
      PREFIX['label'][:prefix] + args[0].to_s.downcase
    when :type
      PREFIX['type'][:prefix] + args[0].to_s.downcase
    when :date
      PREFIX['date'][:prefix] + args[0].getutc.strftime("%Y%m%d%H%M%S")
    when :email
      case args[0]
      when :from then PREFIX['from_email'][:prefix]
      when :to then PREFIX['to_email'][:prefix]
      else raise "Invalid email term type #{args[0]}"
      end + args[1].to_s.downcase
    when :source_id
      PREFIX['source_id'][:prefix] + args[0].to_s.downcase
    when :location
      PREFIX['location'][:prefix] + [args[0]].pack('n') + args[1].to_s
    when :attachment_extension
      PREFIX['attachment_extension'][:prefix] + args[0].to_s.downcase
    when :msgid, :ref, :thread
      PREFIX[type.to_s][:prefix] + args[0][0...(MAX_TERM_LENGTH-1)]
    else
      raise "Invalid term type #{type}"
    end
  end
end

end

class Xapian::Document
  def entry
    Marshal.load data
  end

  def entry=(x)
    self.data = Marshal.dump x
  end

  def index_text text, prefix, weight=1
    term_generator = Xapian::TermGenerator.new
    term_generator.stemmer = Xapian::Stem.new(Redwood::Index::STEM_LANGUAGE)
    term_generator.document = self
    term_generator.index_text text, weight, prefix
  end

  alias old_add_term add_term
  def add_term term
    if term.length <= Redwood::Index::MAX_TERM_LENGTH
      old_add_term term, 0
    else
      warn "dropping excessively long term #{term}"
    end
  end
end
