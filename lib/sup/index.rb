## the index structure for redwood. interacts with ferret.

require 'fileutils'
require 'ferret'
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

  attr_reader :index
  alias ferret index
  def initialize dir=BASE_DIR
    @dir = dir
    @sources = {}
    @sources_dirty = false

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

  def fancy_lock_error_message_for e
    secs = Time.now - e.mtime
    mins = secs.to_i / 60
    time =
      if mins == 0
        "#{secs.to_i} seconds"
      else
        "#{mins} minutes"
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
    raise "duplicate source!" if @sources.include? source
    @sources_dirty = true
    max = @sources.max_of { |id, s| s.is_a?(DraftLoader) || s.is_a?(SentLoader) ? 0 : id }
    source.id ||= (max || 0) + 1
    ##source.id += 1 while @sources.member? source.id
    @sources[source.id] = source
  end

  def source_for uri; @sources.values.find { |s| s.is_source_for? uri }; end
  def usual_sources; @sources.values.find_all { |s| s.usual? }; end
  def sources; @sources.values; end

  def load_index dir=File.join(@dir, "ferret")
    if File.exists? dir
      Redwood::log "loading index..."
      @index = Ferret::Index::Index.new(:path => dir, :analyzer => @analyzer)
      Redwood::log "loaded index of #{@index.size} messages"
    else
      Redwood::log "creating index..."
      field_infos = Ferret::Index::FieldInfos.new :store => :yes
      field_infos.add_field :message_id
      field_infos.add_field :source_id
      field_infos.add_field :source_info
      field_infos.add_field :date, :index => :untokenized
      field_infos.add_field :body, :store => :no
      field_infos.add_field :label
      field_infos.add_field :subject
      field_infos.add_field :from
      field_infos.add_field :to
      field_infos.add_field :refs
      field_infos.add_field :snippet, :index => :no, :term_vector => :no
      field_infos.create_index dir
      @index = Ferret::Index::Index.new(:path => dir, :analyzer => @analyzer)
    end
  end

  ## Syncs the message to the index: deleting if it's already there,
  ## and adding either way. Index state will be determined by m.labels.
  ##
  ## docid and entry can be specified if they're already known.
  def sync_message m, docid=nil, entry=nil
    docid, entry = load_entry_for_id m.id unless docid && entry

    raise "no source info for message #{m.id}" unless m.source && m.source_info
    raise "trying to delete non-corresponding entry #{docid} with index message-id #{@index[docid][:message_id].inspect} and parameter message id #{m.id.inspect}" if docid && @index[docid][:message_id] != m.id

    source_id = 
      if m.source.is_a? Integer
        m.source
      else
        m.source.id or raise "unregistered source #{m.source} (id #{m.source.id.inspect})"
      end

    to = (m.to + m.cc + m.bcc).map { |x| x.email }.join(" ")
    d = {
      :message_id => m.id,
      :source_id => source_id,
      :source_info => m.source_info,
      :date => m.date.to_indexable_s,
      :body => m.content,
      :snippet => m.snippet,
      :label => m.labels.uniq.join(" "),
      :from => m.from ? m.from.email : "",
      :to => (m.to + m.cc + m.bcc).map { |x| x.email }.join(" "),
      :subject => wrap_subj(Message.normalize_subj(m.subj)),
      :refs => (m.refs + m.replytos).uniq.join(" "),
    }

    @index.delete docid if docid
    @index.add_document d
    
    docid, entry = load_entry_for_id m.id
    ## this hasn't been triggered in a long time. TODO: decide whether it's still a problem.
    raise "just added message #{m.id.inspect} but couldn't find it in a search" unless docid
    true
  end

  def save_index fn=File.join(@dir, "ferret")
    # don't have to do anything, apparently
  end

  def contains_id? id
    @index.search(Ferret::Search::TermQuery.new(:message_id, id)).total_hits > 0
  end
  def contains? m; contains_id? m.id; end
  def size; @index.size; end

  ## you should probably not call this on a block that doesn't break
  ## rather quickly because the results can be very large.
  EACH_BY_DATE_NUM = 100
  def each_id_by_date opts={}
    return if @index.size == 0 # otherwise ferret barfs ###TODO: remove this once my ferret patch is accepted
    query = build_query opts
    offset = 0
    while true
      results = @index.search(query, :sort => "date DESC", :limit => EACH_BY_DATE_NUM, :offset => offset)
      Redwood::log "got #{results.total_hits} results for query (offset #{offset}) #{query.inspect}"
      results.hits.each { |hit| yield @index[hit.doc][:message_id], lambda { build_message hit.doc } }
      break if offset >= results.total_hits - EACH_BY_DATE_NUM
      offset += EACH_BY_DATE_NUM
    end
  end

  def num_results_for opts={}
    return 0 if @index.size == 0 # otherwise ferret barfs ###TODO: remove this once my ferret patch is accepted

    q = build_query opts
    index.search(q, :limit => 1).total_hits
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
  def each_message_in_thread_for m, opts={}
    #Redwood::log "Building thread for #{m.id}: #{m.subj}"
    messages = {}
    searched = {}
    num_queries = 0

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

      pending = @index.search(q).hits.map { |hit| @index[hit.doc][:message_id] }
      Redwood::log "found #{pending.size} results for subject query #{q}"
    else
      pending = [m.id]
    end

    until pending.empty? || (opts[:limit] && messages.size >= opts[:limit])
      q = Ferret::Search::BooleanQuery.new true

      pending.each do |id|
        searched[id] = true
        q.add_query Ferret::Search::TermQuery.new(:message_id, id), :should
        q.add_query Ferret::Search::TermQuery.new(:refs, id), :should
      end
      pending = []

      q = build_query :qobj => q

      num_queries += 1
      killed = false
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
    doc = @index[docid]
    source = @sources[doc[:source_id].to_i]
    #puts "building message #{doc[:message_id]} (#{source}##{doc[:source_info]})"
    raise "invalid source #{doc[:source_id]}" unless source

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

  def fresh_thread_id; @next_thread_id += 1; end
  def wrap_subj subj; "__START_SUBJECT__ #{subj} __END_SUBJECT__"; end
  def unwrap_subj subj; subj =~ /__START_SUBJECT__ (.*?) __END_SUBJECT__/ && $1; end

  def drop_entry docno; @index.delete docno; end

  def load_entry_for_id mid
    results = @index.search(Ferret::Search::TermQuery.new(:message_id, mid))
    return if results.total_hits == 0
    docid = results.hits[0].doc
    [docid, @index[docid]]
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
    @index.search_each(q, :sort => "date DESC", :limit => :all) do |docid, score|
      break if contacts.size >= num
      #Redwood::log "got message #{docid} to: #{@index[docid][:to].inspect} and from: #{@index[docid][:from].inspect}"
      f = @index[docid][:from]
      t = @index[docid][:to]

      if AccountManager.is_account_email? f
        t.split(" ").each { |e| contacts[PersonManager.person_for(e)] = true }
      else
        contacts[PersonManager.person_for(f)] = true
      end
    end

    contacts.keys.compact
  end

  def load_sources fn=Redwood::SOURCE_FN
    source_array = (Redwood::load_yaml_obj(fn) || []).map { |o| Recoverable.new o }
    @sources = Hash[*(source_array).map { |s| [s.id, s] }.flatten]
    @sources_dirty = false
  end

  def has_any_from_source_with_label? source, label
    q = Ferret::Search::BooleanQuery.new
    q.add_query Ferret::Search::TermQuery.new("source_id", source.id.to_s), :must
    q.add_query Ferret::Search::TermQuery.new("label", label.to_s), :must
    index.search(q, :limit => 1).total_hits > 0
  end

protected

  ## do any specialized parsing
  ## returns nil and flashes error message if parsing failed
  def parse_user_query_string str
    result = str.gsub(/\b(to|from):(\S+)\b/) do
      field, name = $1, $2
      if(p = ContactManager.contact_for(name))
        [field, p.email]
      elsif name == "me"
        [field, "(" + AccountManager.user_emails.join("||") + ")"]
      else
        [field, name]
      end.join(":")
    end
    
    if $have_chronic
      chronic_failure = false
      result = result.gsub(/\b(before|on|in|after):(\((.+?)\)\B|(\S+)\b)/) do
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
          BufferManager.flash "Don't understand date #{datestr.inspect}!"
          chronic_failure = true
        end
      end
      result = nil if chronic_failure
    end
    
    Redwood::log "translated #{str.inspect} to #{result}" unless result == str
    @qparser.parse result if result
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
    if @sources_dirty || @sources.any? { |id, s| s.dirty? }
      bakfn = fn + ".bak"
      if File.exists? fn
        File.chmod 0600, fn
        FileUtils.mv fn, bakfn, :force => true unless File.exists?(bakfn) && File.size(fn) == 0
      end
      Redwood::save_yaml_obj @sources.values.sort_by { |s| s.id.to_i }, fn, true
      File.chmod 0600, fn
    end
    @sources_dirty = false
  end
end

end
