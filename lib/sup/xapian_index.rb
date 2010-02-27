ENV["XAPIAN_FLUSH_THRESHOLD"] = "1000"

require 'xapian'
require 'set'

module Redwood

# This index implementation uses Xapian for searching and storage. It
# tends to be slightly faster than Ferret for indexing and significantly faster
# for searching due to precomputing thread membership.
class XapianIndex < BaseIndex
  STEM_LANGUAGE = "english"
  INDEX_VERSION = '2'

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

  def initialize dir=BASE_DIR
    super

    @index_mutex = Monitor.new
  end

  def load_index
    path = File.join(@dir, 'xapian')
    if File.exists? path
      @xapian = Xapian::WritableDatabase.new(path, Xapian::DB_OPEN)
      db_version = @xapian.get_metadata 'version'
      db_version = '0' if db_version.empty?
      if db_version == '1'
        info "Upgrading index format 1 to 2"
        @xapian.set_metadata 'version', INDEX_VERSION
      elsif db_version != INDEX_VERSION
        fail "This Sup version expects a v#{INDEX_VERSION} index, but you have an existing v#{db_version} index. Please downgrade to your previous version and dump your labels before upgrading to this version (then run sup-sync --restore)."
      end
    else
      @xapian = Xapian::WritableDatabase.new(path, Xapian::DB_CREATE)
      @xapian.set_metadata 'version', INDEX_VERSION
    end
    @enquire = Xapian::Enquire.new @xapian
    @enquire.weighting_scheme = Xapian::BoolWeight.new
    @enquire.docid_order = Xapian::Enquire::ASCENDING
  end

  def save_index
    info "Flushing Xapian updates to disk. This may take a while..."
    @xapian.flush
  end

  def optimize
  end

  def size
    synchronize { @xapian.doccount }
  end

  def contains_id? id
    synchronize { find_docid(id) && true }
  end

  def source_for_id id
    synchronize { get_entry(id)[:source_id] }
  end

  def delete id
    synchronize { @xapian.delete_document mkterm(:msgid, id) }
  end

  def build_message id
    entry = synchronize { get_entry id }
    return unless entry

    source = SourceManager[entry[:source_id]]
    raise "invalid source #{entry[:source_id]}" unless source

    m = Message.new :source => source, :source_info => entry[:source_info],
                    :labels => entry[:labels], :snippet => entry[:snippet]

    mk_person = lambda { |x| Person.new(*x.reverse!) }
    entry[:from] = mk_person[entry[:from]]
    entry[:to].map!(&mk_person)
    entry[:cc].map!(&mk_person)
    entry[:bcc].map!(&mk_person)

    m.load_from_index! entry
    m
  end

  def add_message m; sync_message m, true end
  def update_message m; sync_message m, true end
  def update_message_state m; sync_message m, false end

  def num_results_for query={}
    xapian_query = build_xapian_query query
    matchset = run_query xapian_query, 0, 0, 100
    matchset.matches_estimated
  end

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

  def each_id_by_date query={}
    each_id(query) { |id| yield id, lambda { build_message id } }
  end

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

  def load_contacts emails, opts={}
    contacts = Set.new
    num = opts[:num] || 20
    each_id_by_date :participants => emails do |id,b|
      break if contacts.size >= num
      m = b.call
      ([m.from]+m.to+m.cc+m.bcc).compact.each { |p| contacts << [p.name, p.email] }
    end
    contacts.to_a.compact.map { |n,e| Person.new n, e }[0...num]
  end

  # TODO share code with the Ferret index
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
    NORMAL_PREFIX.each { |k,vs| vs.each { |v| qp.add_prefix k, v } }
    BOOLEAN_PREFIX.each { |k,vs| vs.each { |v| qp.add_boolean_prefix k, v } }
    xapian_query = qp.parse_query(subs, Xapian::QueryParser::FLAG_PHRASE|Xapian::QueryParser::FLAG_BOOLEAN|Xapian::QueryParser::FLAG_LOVEHATE|Xapian::QueryParser::FLAG_WILDCARD)

    debug "parsed xapian query: #{xapian_query.description}"

    raise ParseError if xapian_query.nil? or xapian_query.empty?
    query[:qobj] = xapian_query
    query[:text] = s
    query
  end

  private

  # Stemmed
  NORMAL_PREFIX = {
    'subject' => 'S',
    'body' => 'B',
    'from_name' => 'FN',
    'to_name' => 'TN',
    'name' => %w(FN TN),
    'attachment' => 'A',
    'email_text' => 'E',
    '' => %w(S B FN TN A E),
  }

  # Unstemmed
  BOOLEAN_PREFIX = {
    'type' => 'K',
    'from_email' => 'FE',
    'to_email' => 'TE',
    'email' => %w(FE TE),
    'date' => 'D',
    'label' => 'L',
    'source_id' => 'I',
    'attachment_extension' => 'O',
    'msgid' => 'Q',
    'id' => 'Q',
    'thread' => 'H',
    'ref' => 'R',
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
    Marshal.load doc.data
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
      :source_id => m.source.id,
      :source_info => m.source_info,
      :date => m.date,
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
        doc.index_text p.name, PREFIX["#{d}_name"] if p.name
        doc.index_text p.email, PREFIX['email_text']
        doc.add_term mkterm(:email, d, p.email)
      end
    end

    person_termer[:from][m.from] if m.from
    (m.to+m.cc+m.bcc).each(&(person_termer[:to]))

    # Full text search content
    subject_text = m.indexable_subject
    body_text = m.indexable_body
    doc.index_text subject_text, PREFIX['subject']
    doc.index_text body_text, PREFIX['body']
    m.attachments.each { |a| doc.index_text a, PREFIX['attachment'] }

    # Miscellaneous terms
    doc.add_term mkterm(:date, m.date) if m.date
    doc.add_term mkterm(:type, 'mail')
    doc.add_term mkterm(:msgid, m.id)
    doc.add_term mkterm(:source_id, m.source.id)
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
      PREFIX['label'] + args[0].to_s.downcase
    when :type
      PREFIX['type'] + args[0].to_s.downcase
    when :date
      PREFIX['date'] + args[0].getutc.strftime("%Y%m%d%H%M%S")
    when :email
      case args[0]
      when :from then PREFIX['from_email']
      when :to then PREFIX['to_email']
      else raise "Invalid email term type #{args[0]}"
      end + args[1].to_s.downcase
    when :source_id
      PREFIX['source_id'] + args[0].to_s.downcase
    when :attachment_extension
      PREFIX['attachment_extension'] + args[0].to_s.downcase
    when :msgid, :ref, :thread
      PREFIX[type.to_s] + args[0][0...(MAX_TERM_LENGTH-1)]
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
    term_generator.stemmer = Xapian::Stem.new(Redwood::XapianIndex::STEM_LANGUAGE)
    term_generator.document = self
    term_generator.index_text text, weight, prefix
  end

  alias old_add_term add_term
  def add_term term
    if term.length <= Redwood::XapianIndex::MAX_TERM_LENGTH
      old_add_term term, 0
    else
      warn "dropping excessively long term #{term}"
    end
  end
end
