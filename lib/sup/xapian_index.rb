require 'xapian'
require 'gdbm'
require 'set'

module Redwood

# This index implementation uses Xapian for searching and GDBM for storage. It
# tends to be slightly faster than Ferret for indexing and significantly faster
# for searching due to precomputing thread membership.
class XapianIndex < BaseIndex
  STEM_LANGUAGE = "english"

  ## dates are converted to integers for xapian, and are used for document ids,
  ## so we must ensure they're reasonably valid. this typically only affect
  ## spam.
  MIN_DATE = Time.at 0
  MAX_DATE = Time.at(2**31-1)

  def initialize dir=BASE_DIR
    super

    @index_mutex = Monitor.new
  end

  def load_index
    @entries = MarshalledGDBM.new File.join(@dir, "entries.db")
    @docids = MarshalledGDBM.new File.join(@dir, "docids.db")
    @thread_members = MarshalledGDBM.new File.join(@dir, "thread_members.db")
    @thread_ids = MarshalledGDBM.new File.join(@dir, "thread_ids.db")
    @assigned_docids = GDBM.new File.join(@dir, "assigned_docids.db")

    @xapian = Xapian::WritableDatabase.new(File.join(@dir, "xapian"), Xapian::DB_CREATE_OR_OPEN)
    @term_generator = Xapian::TermGenerator.new()
    @term_generator.stemmer = Xapian::Stem.new(STEM_LANGUAGE)
    @enquire = Xapian::Enquire.new @xapian
    @enquire.weighting_scheme = Xapian::BoolWeight.new
    @enquire.docid_order = Xapian::Enquire::ASCENDING
  end

  def save_index
  end

  def optimize
  end

  def size
    synchronize { @xapian.doccount }
  end

  def contains_id? id
    synchronize { @entries.member? id }
  end

  def source_for_id id
    synchronize { @entries[id][:source_id] }
  end

  def delete id
    synchronize { @xapian.delete_document @docids[id] }
  end

  def build_message id
    entry = synchronize { @entries[id] }
    return unless entry

    source = SourceManager[entry[:source_id]]
    raise "invalid source #{entry[:source_id]}" unless source

    mk_addrs = lambda { |l| l.map { |e,n| "#{n} <#{e}>" } * ', ' }
    mk_refs = lambda { |l| l.map { |r| "<#{r}>" } * ' ' }
    fake_header = {
      'message-id' => entry[:message_id],
      'date' => Time.at(entry[:date]),
      'subject' => entry[:subject],
      'from' => mk_addrs[[entry[:from]]],
      'to' => mk_addrs[entry[:to]],
      'cc' => mk_addrs[entry[:cc]],
      'bcc' => mk_addrs[entry[:bcc]],
      'reply-tos' => mk_refs[entry[:replytos]],
      'references' => mk_refs[entry[:refs]],
     }

      m = Message.new :source => source, :source_info => entry[:source_info],
                  :labels => entry[:labels],
                  :snippet => entry[:snippet]
      m.parse_header fake_header
      m
  end

  def sync_message m, opts={}
    entry = synchronize { @entries[m.id] }
    snippet = m.snippet
    entry ||= {}
    labels = m.labels
    entry = {} if opts[:force_overwrite]

    d = {
      :message_id => m.id,
      :source_id => m.source.id,
      :source_info => m.source_info,
      :date => (entry[:date] || m.date),
      :snippet => snippet,
      :labels => labels,
      :from => (entry[:from] || [m.from.email, m.from.name]),
      :to => (entry[:to] || m.to.map { |p| [p.email, p.name] }),
      :cc => (entry[:cc] || m.cc.map { |p| [p.email, p.name] }),
      :bcc => (entry[:bcc] || m.bcc.map { |p| [p.email, p.name] }),
      :subject => m.subj,
      :refs => (entry[:refs] || m.refs),
      :replytos => (entry[:replytos] || m.replytos),
    }

    labels.each { |l| LabelManager << l }

    synchronize do
      index_message m, opts
      union_threads([m.id] + m.refs + m.replytos)
      @entries[m.id] = d
    end
    true
  end

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
    # TODO handle killed threads
    ids = synchronize { @thread_members[@thread_ids[m.id]] } || []
    ids.select { |id| contains_id? id }.each { |id| yield id, lambda { build_message id } }
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
        Redwood::log "filename - translated #{field}:#{name} to attachment:\"#{name.downcase}\""
        "attachment:\"#{name.downcase}\""
      when "filetype"
        Redwood::log "filetype - translated #{field}:#{name} to attachment_extension:#{name.downcase}"
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
            Redwood::log "chronic: translated #{field}:#{datestr} to #{realdate.end}"
            "date:#{realdate.end.to_i}..#{lastdate}"
          when "before"
            Redwood::log "chronic: translated #{field}:#{datestr} to #{realdate.begin}"
            "date:#{firstdate}..#{realdate.end.to_i}"
          else
            Redwood::log "chronic: translated #{field}:#{datestr} to #{realdate}"
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

    qp = Xapian::QueryParser.new
    qp.database = @xapian
    qp.stemmer = Xapian::Stem.new(STEM_LANGUAGE)
    qp.stemming_strategy = Xapian::QueryParser::STEM_SOME
    qp.default_op = Xapian::Query::OP_AND
    qp.add_valuerangeprocessor(Xapian::NumberValueRangeProcessor.new(DATE_VALUENO, 'date:', true))
    NORMAL_PREFIX.each { |k,v| qp.add_prefix k, v }
    BOOLEAN_PREFIX.each { |k,v| qp.add_boolean_prefix k, v }
    xapian_query = qp.parse_query(subs, Xapian::QueryParser::FLAG_PHRASE|Xapian::QueryParser::FLAG_BOOLEAN|Xapian::QueryParser::FLAG_LOVEHATE|Xapian::QueryParser::FLAG_WILDCARD, PREFIX['body'])

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
    'name' => 'N',
    'attachment' => 'A',
  }

  # Unstemmed
  BOOLEAN_PREFIX = {
    'type' => 'K',
    'from_email' => 'FE',
    'to_email' => 'TE',
    'email' => 'E',
    'date' => 'D',
    'label' => 'L',
    'source_id' => 'I',
    'attachment_extension' => 'O',
  }

  PREFIX = NORMAL_PREFIX.merge BOOLEAN_PREFIX

  DATE_VALUENO = 0

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
    begin
      while @assigned_docids.member? [docid].pack("N")
        docid -= 1
      end
    rescue
    end
    @assigned_docids[[docid].pack("N")] = ''
    docid
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
    matchset.matches.map { |r| r.document.data }
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
      participant_terms = opts[:participants].map { |p| mkterm(:email,:any, (Redwood::Person === p) ? p.email : p) }
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

  def index_message m, opts
    terms = []
    text = []

    subject_text = m.indexable_subject
    body_text = m.indexable_body

    # Person names are indexed with several prefixes
    person_termer = lambda do |d|
      lambda do |p|
        ["#{d}_name", "name", "body"].each do |x|
          text << [p.name, PREFIX[x]]
        end if p.name
        [d, :any].each { |x| terms << mkterm(:email, x, p.email) }
      end
    end

    person_termer[:from][m.from] if m.from
    (m.to+m.cc+m.bcc).each(&(person_termer[:to]))

    terms << mkterm(:date,m.date) if m.date
    m.labels.each { |t| terms << mkterm(:label,t) }
    terms << mkterm(:type, 'mail')
    terms << mkterm(:source_id, m.source.id)
    m.attachments.each do |a|
      a =~ /\.(\w+)$/ or next
      t = mkterm(:attachment_extension, $1)
      terms << t
    end

    # Full text search content
    text << [subject_text, PREFIX['subject']]
    text << [subject_text, PREFIX['body']]
    text << [body_text, PREFIX['body']]
    m.attachments.each { |a| text << [a, PREFIX['attachment']] }

    truncated_date = if m.date < MIN_DATE
      Redwood::log "warning: adjusting too-low date #{m.date} for indexing"
      MIN_DATE
    elsif m.date > MAX_DATE
      Redwood::log "warning: adjusting too-high date #{m.date} for indexing"
      MAX_DATE
    else
      m.date
    end

    # Date value for range queries
    date_value = begin
      Xapian.sortable_serialise truncated_date.to_i
    rescue TypeError
      Xapian.sortable_serialise 0
    end

    doc = Xapian::Document.new
    docid = @docids[m.id] || assign_docid(m, truncated_date)

    @term_generator.document = doc
    text.each { |text,prefix| @term_generator.index_text text, 1, prefix }
    terms.each { |term| doc.add_term term if term.length <= MAX_TERM_LENGTH }
    doc.add_value DATE_VALUENO, date_value
    doc.data = m.id

    @xapian.replace_document docid, doc
    @docids[m.id] = docid
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
      when :any then PREFIX['email']
      else raise "Invalid email term type #{args[0]}"
      end + args[1].to_s.downcase
    when :source_id
      PREFIX['source_id'] + args[0].to_s.downcase
    when :attachment_extension
      PREFIX['attachment_extension'] + args[0].to_s.downcase
    else
      raise "Invalid term type #{type}"
    end
  end

  # Join all the given message-ids into a single thread
  def union_threads ids
    seen_threads = Set.new
    related = Set.new

    # Get all the ids that will be in the new thread
    ids.each do |id|
      related << id
      thread_id = @thread_ids[id]
      if thread_id && !seen_threads.member?(thread_id)
        thread_members = @thread_members[thread_id]
        related.merge thread_members
        seen_threads << thread_id
      end
    end

    # Pick a leader and move all the others to its thread
    a = related.to_a
    best, *rest = a.sort_by { |x| x.hash }
    @thread_members[best] = a
    @thread_ids[best] = best
    rest.each do |x|
      @thread_members.delete x
      @thread_ids[x] = best
    end
  end
end

end

class MarshalledGDBM < GDBM
  def []= k, v
    super k, Marshal.dump(v)
  end

  def [] k
    v = super k
    v ? Marshal.load(v) : nil
  end
end
