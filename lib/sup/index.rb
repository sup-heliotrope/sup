## the index structure for redwood. interacts with ferret.

require 'thread'
require 'fileutils'
require 'ferret'
#require_gem 'ferret', ">= 0.10.13"

module Redwood

class IndexError < StandardError
  attr_reader :source

  def initialize source, s
    super s
    @source = source
  end
end

class Index
  include Singleton

  attr_reader :index # debugging only
  
  def initialize dir=BASE_DIR
    @dir = dir
    @sources = {}
    @sources_dirty = false

    wsa = Ferret::Analysis::WhiteSpaceAnalyzer.new false
    sa = Ferret::Analysis::StandardAnalyzer.new Ferret::Analysis::FULL_ENGLISH_STOP_WORDS, true
    @analyzer = Ferret::Analysis::PerFieldAnalyzer.new wsa
    @analyzer[:body] = sa
    @qparser ||= Ferret::QueryParser.new :default_field => :body, :analyzer => @analyzer

    self.class.i_am_the_instance self
  end

  def load
    load_sources
    load_index
  end

  def save
    FileUtils.mkdir_p @dir unless File.exists? @dir
    save_sources
    save_index
  end

  def add_source source
    raise "duplicate source!" if @sources.include? source
    @sources_dirty = true
    source.id ||= @sources.size
    ##TODO: why was this necessary?
    ##source.id += 1 while @sources.member? source.id
    @sources[source.id] = source
  end

  def source_for name; @sources.values.find { |s| s.is_source_for? name }; end
  def usual_sources; @sources.values.find_all { |s| s.usual? }; end

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

  ## update the message by deleting and re-adding
  def update_message m, source=nil, source_info=nil
    docid, entry = load_entry_for_id m.id
    if entry
      source ||= entry[:source_id].to_i
      source_info ||= entry[:source_info].to_i
    end

    ## this happens sometimes. i'm not sure why. ferret bug?
    raise "no entry and no source info for message #{m.id}: source #{source.inspect}, info #{source_info.inspect}, entry #{entry.inspect}, query #{Ferret::Search::TermQuery.new(:message_id, m.id)}, results #{@index.search(Ferret::Search::TermQuery.new(:message_id, m.id)).inspect}" unless source && source_info

    raise "deleting non-corresponding entry #{docid}" unless @index[docid][:message_id] == m.id
    @index.delete docid
    add_message m
  end

  def save_index fn=File.join(@dir, "ferret")
    # don't have to do anything apparently
  end

  def contains_id? id
    @index.search(Ferret::Search::TermQuery.new(:message_id, id)).total_hits > 0
  end
  def contains? m; contains_id? m.id; end
  def size; @index.size; end

  ## you should probably not call this on a block that doesn't break
  ## rather quickly because the results will probably be, as we say
  ## in scotland, frikkin' huuuge.
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
    index.search(q).total_hits
  end

  ## yield all messages in the thread containing 'm' by repeatedly
  ## querying the index.  yields pairs of message ids and
  ## message-building lambdas, so that building an unwanted message
  ## can be skipped in the block if desired.
  SAME_SUBJECT_DATE_LIMIT = 7
  def each_message_in_thread_for m, opts={}
    messages = {}
    searched = {}
    num_queries = 0

    ## temporarily disabling subject searching because it's a
    ## significant slowdown.
    ##
    ## TODO: make this configurable, i guess
    if false
      date_min = m.date - (SAME_SUBJECT_DATE_LIMIT * 12 * 3600)
      date_max = m.date + (SAME_SUBJECT_DATE_LIMIT * 12 * 3600)

      q = Ferret::Search::BooleanQuery.new true
      sq = Ferret::Search::PhraseQuery.new(:subject)
      wrap_subj(Message.normalize_subj(m.subj)).split(/\s+/).each do |t|
        sq.add_term t
      end
      q.add_query sq, :must
      q.add_query Ferret::Search::RangeQuery.new(:date, :>= => date_min.to_indexable_s, :<= => date_max.to_indexable_s), :must

      pending = @index.search(q).hits.map { |hit| @index[hit.doc][:message_id] }
      Redwood::log "found #{pending.size} results for subject query #{q}"
    else
      pending = [m.id]
    end

    until pending.empty? || (opts[:limit] && messages.size >= opts[:limit])
      id = pending.pop
      next if searched.member? id
      searched[id] = true
      q = Ferret::Search::BooleanQuery.new true
      q.add_query Ferret::Search::TermQuery.new(:message_id, id), :should
      q.add_query Ferret::Search::TermQuery.new(:refs, id), :should

      num_queries += 1
      @index.search_each(q, :limit => :all) do |docid, score|
        break if opts[:limit] && messages.size >= opts[:limit]
        mid = @index[docid][:message_id]
        unless messages.member? mid
          messages[mid] ||= lambda { build_message docid }
          refs = @index[docid][:refs].split(" ")
          pending += refs
        end
      end
    end
    Redwood::log "ran #{num_queries} queries to build thread of #{messages.size} messages for #{m.id}"
    messages.each { |mid, builder| yield mid, builder }
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
      "to" => doc[:to],
      "message-id" => doc[:message_id],
      "references" => doc[:refs],
    }

    Message.new :source => source, :source_info => doc[:source_info].to_i, 
                :labels => doc[:label].split(" ").map { |s| s.intern },
                :snippet => doc[:snippet], :header => fake_header
  end

  def fresh_thread_id; @next_thread_id += 1; end
  def wrap_subj subj; "__START_SUBJECT__ #{subj} __END_SUBJECT__"; end
  def unwrap_subj subj; subj =~ /__START_SUBJECT__ (.*?) __END_SUBJECT__/ && $1; end

  def add_message m
    return false if contains? m

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
      :label => m.labels.join(" "),
      :from => m.from ? m.from.email : "",
      :to => (m.to + m.cc + m.bcc).map { |x| x.email }.join(" "),
      :subject => wrap_subj(Message.normalize_subj(m.subj)),
      :refs => (m.refs + m.replytos).uniq.join(" "),
    }

    @index.add_document d
    
    ## TODO: figure out why this is sometimes triggered
    #docid, entry = load_entry_for_id m.id
    #raise "just added message #{m.id} but couldn't find it in a search" unless docid
    true
  end

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
      #Redwood::log "got message with to: #{@index[docid][:to].inspect} and from: #{@index[docid][:from].inspect}"
      f = @index[docid][:from]
      t = @index[docid][:to]

      if AccountManager.is_account_email? f
        t.split(" ").each { |e| #Redwood::log "adding #{e} because there's a message to him from account email #{f}"; 
          contacts[Person.for(e)] = true }
      else
        #Redwood::log "adding from #{f} because there's a message from him to #{t}"
        contacts[Person.for(f)] = true
      end
    end

    contacts.keys.compact
  end

protected

  def parse_user_query_string str; @qparser.parse str; end
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
    query.add_query Ferret::Search::TermQuery.new("label", "killed"), :must_not unless opts[:load_killed] || labels.include?(:killed)
    query
  end

  def load_sources fn=Redwood::SOURCE_FN
    @sources = Hash[*(Redwood::load_yaml_obj(fn) || []).map { |s| [s.id, s] }.flatten]
    @sources_dirty = false
  end

  def save_sources fn=Redwood::SOURCE_FN
    if @sources_dirty || @sources.any? { |id, s| s.dirty? }
      bakfn = fn + ".bak"
      if File.exists? fn
        File.chmod 0600, fn
        FileUtils.mv fn, bakfn, :force => true unless File.exists?(bakfn) && File.size(bakfn) > File.size(fn)
      end
      Redwood::save_yaml_obj @sources.values, fn
      File.chmod 0600, fn
    end
    @sources_dirty = false
  end
end

end
