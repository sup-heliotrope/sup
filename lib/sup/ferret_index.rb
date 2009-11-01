require 'ferret'

module Redwood

class FerretIndex < BaseIndex

  HookManager.register "custom-search", <<EOS
Executes before a string search is applied to the index,
returning a new search string.
Variables:
  subs: The string being searched.
EOS

  def initialize dir=BASE_DIR
    super

    @index_mutex = Monitor.new
    wsa = Ferret::Analysis::WhiteSpaceAnalyzer.new false
    sa = Ferret::Analysis::StandardAnalyzer.new [], true
    @analyzer = Ferret::Analysis::PerFieldAnalyzer.new wsa
    @analyzer[:body] = sa
    @analyzer[:subject] = sa
    @qparser ||= Ferret::QueryParser.new :default_field => :body, :analyzer => @analyzer, :or_default => false
  end

  def load_index dir=File.join(@dir, "ferret")
    if File.exists? dir
      debug "loading index..."
      @index_mutex.synchronize do
        @index = Ferret::Index::Index.new(:path => dir, :analyzer => @analyzer, :id_field => 'message_id')
        debug "loaded index of #{@index.size} messages"
      end
    else
      debug "creating index..."
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
        @index = Ferret::Index::Index.new(:path => dir, :analyzer => @analyzer, :id_field => 'message_id')
      end
    end
  end

  def add_message m; sync_message m end
  def update_message m; sync_message m end
  def update_message_state m; sync_message m end

  def sync_message m, opts={}
    entry = @index[m.id]

    raise "no source info for message #{m.id}" unless m.source && m.source_info

    source_id = if m.source.is_a? Integer
      m.source
    else
      m.source.id or raise "unregistered source #{m.source} (id #{m.source.id.inspect})"
    end

    snippet = if m.snippet_contains_encrypted_content? && $config[:discard_snippets_from_encrypted_messages]
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
    labels = m.labels # override because this is the new state, unless...

    ## if we are a later version of a message, ignore what's in the index,
    ## but merge in the labels.
    if entry[:source_id] && entry[:source_info] && entry[:label] &&
      ((entry[:source_id].to_i > source_id) || (entry[:source_info].to_i < m.source_info))
      labels += entry[:label].to_set_of_symbols
      #debug "found updated version of message #{m.id}: #{m.subj}"
      #debug "previous version was at #{entry[:source_id].inspect}:#{entry[:source_info].inspect}, this version at #{source_id.inspect}:#{m.source_info.inspect}"
      #debug "merged labels are #{labels.inspect} (index #{entry[:label].inspect}, message #{m.labels.inspect})"
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
      :label => labels.to_a.join(" "),
      :attachments => (entry[:attachments] || m.attachments.uniq.join(" ")),

      ## always override :from and :to.
      ## older versions of Sup would often store the wrong thing in the index
      ## (because they were canonicalizing email addresses, resulting in the
      ## wrong name associated with each.) the correct address is read from
      ## the original header when these messages are opened in thread-view-mode,
      ## so this allows people to forcibly update the address in the index by
      ## marking those threads for saving.
      :from => (m.from ? m.from.indexable_content : ""),
      :to => (m.to + m.cc + m.bcc).map { |x| x.indexable_content }.join(" "),

      ## always overwrite :refs.
      ## these might have changed due to manual thread joining.
      :refs => (m.refs + m.replytos).uniq.join(" "),

      :subject => (entry[:subject] || wrap_subj(Message.normalize_subj(m.subj))),
    }

    @index_mutex.synchronize do
      @index.delete m.id
      @index.add_document d
    end
  end
  private :sync_message

  def save_index fn=File.join(@dir, "ferret")
    # don't have to do anything, apparently
  end

  def contains_id? id
    @index_mutex.synchronize { @index.search(Ferret::Search::TermQuery.new(:message_id, id)).total_hits > 0 }
  end

  def size
    @index_mutex.synchronize { @index.size }
  end

  EACH_BY_DATE_NUM = 100
  def each_id_by_date query={}
    return if empty? # otherwise ferret barfs ###TODO: remove this once my ferret patch is accepted
    ferret_query = build_ferret_query query
    offset = 0
    while true
      limit = (query[:limit])? [EACH_BY_DATE_NUM, query[:limit] - offset].min : EACH_BY_DATE_NUM
      results = @index_mutex.synchronize { @index.search ferret_query, :sort => "date DESC", :limit => limit, :offset => offset }
      debug "got #{results.total_hits} results for query (offset #{offset}) #{ferret_query.inspect}"
      results.hits.each do |hit|
        yield @index_mutex.synchronize { @index[hit.doc][:message_id] }, lambda { build_message hit.doc }
      end
      break if query[:limit] and offset >= query[:limit] - limit
      break if offset >= results.total_hits - limit
      offset += limit
    end
  end

  def num_results_for query={}
    return 0 if empty? # otherwise ferret barfs ###TODO: remove this once my ferret patch is accepted
    ferret_query = build_ferret_query query
    @index_mutex.synchronize { @index.search(ferret_query, :limit => 1).total_hits }
  end

  SAME_SUBJECT_DATE_LIMIT = 7
  MAX_CLAUSES = 1000
  def each_message_in_thread_for m, opts={}
    #debug "Building thread for #{m.id}: #{m.subj}"
    messages = {}
    searched = {}
    num_queries = 0

    pending = [m.id]
    if $config[:thread_by_subject] # do subject queries
      date_min = m.date - (SAME_SUBJECT_DATE_LIMIT * 12 * 3600)
      date_max = m.date + (SAME_SUBJECT_DATE_LIMIT * 12 * 3600)

      q = Ferret::Search::BooleanQuery.new true
      sq = Ferret::Search::PhraseQuery.new(:subject)
      wrap_subj(Message.normalize_subj(m.subj)).split.each do |t|
        sq.add_term t
      end
      q.add_query sq, :must
      q.add_query Ferret::Search::RangeQuery.new(:date, :>= => date_min.to_indexable_s, :<= => date_max.to_indexable_s), :must

      q = build_ferret_query :qobj => q

      p1 = @index_mutex.synchronize { @index.search(q).hits.map { |hit| @index[hit.doc][:message_id] } }
      debug "found #{p1.size} results for subject query #{q}"

      p2 = @index_mutex.synchronize { @index.search(q.to_s, :limit => :all).hits.map { |hit| @index[hit.doc][:message_id] } }
      debug "found #{p2.size} results in string form"

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

      q = build_ferret_query :qobj => q

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
            #debug "got #{mid} as a child of #{id}"
            messages[mid] ||= lambda { build_message docid }
            refs = @index[docid][:refs].split
            pending += refs.select { |id| !searched[id] }
          end
        end
      end
    end

    if killed
      #debug "thread for #{m.id} is killed, ignoring"
      false
    else
      #debug "ran #{num_queries} queries to build thread of #{messages.size} messages for #{m.id}: #{m.subj}" if num_queries > 0
      messages.each { |mid, builder| yield mid, builder }
      true
    end
  end

  ## builds a message object from a ferret result
  def build_message docid
    @index_mutex.synchronize do
      doc = @index[docid] or return

      source = SourceManager[doc[:source_id].to_i]
      raise "invalid source #{doc[:source_id]}" unless source

      #puts "building message #{doc[:message_id]} (#{source}##{doc[:source_info]})"

      fake_header = {
        "date" => Time.at(doc[:date].to_i),
        "subject" => unwrap_subj(doc[:subject]),
        "from" => doc[:from],
        "to" => doc[:to].split.join(", "), # reformat
        "message-id" => doc[:message_id],
        "references" => doc[:refs].split.map { |x| "<#{x}>" }.join(" "),
      }

      m = Message.new :source => source, :source_info => doc[:source_info].to_i,
                  :labels => doc[:label].to_set_of_symbols,
                  :snippet => doc[:snippet]
      m.parse_header fake_header
      m
    end
  end

  def delete id
    @index_mutex.synchronize { @index.delete id }
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

    debug "contact search: #{q}"
    contacts = {}
    num = h[:num] || 20
    @index_mutex.synchronize do
      @index.search_each q, :sort => "date DESC", :limit => :all do |docid, score|
        break if contacts.size >= num
        #debug "got message #{docid} to: #{@index[docid][:to].inspect} and from: #{@index[docid][:from].inspect}"
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

  def each_id query={}
    ferret_query = build_ferret_query query
    results = @index_mutex.synchronize { @index.search ferret_query, :limit => (query[:limit] || :all) }
    results.hits.map { |hit| yield @index[hit.doc][:message_id] }
  end

  def optimize
    @index_mutex.synchronize { @index.optimize }
  end

  def source_for_id id
    entry = @index[id]
    return unless entry
    entry[:source_id].to_i
  end

  class ParseError < StandardError; end

  ## parse a query string from the user. returns a query object
  ## that can be passed to any index method with a 'query'
  ## argument, as well as build_ferret_query.
  ##
  ## raises a ParseError if something went wrong.
  def parse_query s
    query = {}

    subs = HookManager.run("custom-search", :subs => s) || s
    subs = subs.gsub(/\b(to|from):(\S+)\b/) do
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
        debug "filename: translated #{field}:#{name} to attachments:(#{name.downcase})"
        "attachments:(#{name.downcase})"
      when "filetype"
        debug "filetype: translated #{field}:#{name} to attachments:(*.#{name.downcase})"
        "attachments:(*.#{name.downcase})"
      end
    end

    if $have_chronic
      subs = subs.gsub(/\b(before|on|in|during|after):(\((.+?)\)\B|(\S+)\b)/) do
        field, datestr = $1, ($3 || $4)
        realdate = Chronic.parse datestr, :guess => false, :context => :past
        if realdate
          case field
          when "after"
            debug "chronic: translated #{field}:#{datestr} to #{realdate.end}"
            "date:(>= #{sprintf "%012d", realdate.end.to_i})"
          when "before"
            debug "chronic: translated #{field}:#{datestr} to #{realdate.begin}"
            "date:(<= #{sprintf "%012d", realdate.begin.to_i})"
          else
            debug "chronic: translated #{field}:#{datestr} to #{realdate}"
            "date:(<= #{sprintf "%012d", realdate.end.to_i}) date:(>= #{sprintf "%012d", realdate.begin.to_i})"
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

    begin
      query[:qobj] = @qparser.parse(subs)
      query[:text] = s
      query
    rescue Ferret::QueryParser::QueryParseException => e
      raise ParseError, e.message
    end
  end

private

  def build_ferret_query query
    q = Ferret::Search::BooleanQuery.new
    q.add_query Ferret::Search::MatchAllQuery.new, :must
    q.add_query query[:qobj], :must if query[:qobj]
    labels = ([query[:label]] + (query[:labels] || [])).compact
    labels.each { |t| q.add_query Ferret::Search::TermQuery.new("label", t.to_s), :must }
    if query[:participants]
      q2 = Ferret::Search::BooleanQuery.new
      query[:participants].each do |p|
        q2.add_query Ferret::Search::TermQuery.new("from", p.email), :should
        q2.add_query Ferret::Search::TermQuery.new("to", p.email), :should
      end
      q.add_query q2, :must
    end

    q.add_query Ferret::Search::TermQuery.new("label", "spam"), :must_not unless query[:load_spam] || labels.include?(:spam)
    q.add_query Ferret::Search::TermQuery.new("label", "deleted"), :must_not unless query[:load_deleted] || labels.include?(:deleted)
    q.add_query Ferret::Search::TermQuery.new("label", "killed"), :must_not if query[:skip_killed]

    q.add_query Ferret::Search::TermQuery.new("source_id", query[:source_id]), :must if query[:source_id]
    q
  end

  def wrap_subj subj; "__START_SUBJECT__ #{subj} __END_SUBJECT__"; end
  def unwrap_subj subj; subj =~ /__START_SUBJECT__ (.*?) __END_SUBJECT__/ && $1; end
end

end
