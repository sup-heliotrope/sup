## Index interface, subclassed by Ferret indexer.

require 'fileutils'

begin
  require 'chronic'
  $have_chronic = true
rescue LoadError => e
  Redwood::log "optional 'chronic' library not found (run 'gem install chronic' to install)"
  $have_chronic = false
end

module Redwood

class BaseIndex
  include InteractiveLock

  class LockError < StandardError
    def initialize h
      @h = h
    end

    def method_missing m; @h[m.to_s] end
  end

  include Singleton

  def initialize dir=BASE_DIR
    @dir = dir
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

  def unlock
    if @lock && @lock.locked?
      Redwood::log "unlocking #{lockfile}..."
      @lock.unlock
    end
  end

  def load
    SourceManager.load_sources
    load_index
  end

  def save
    Redwood::log "saving index and sources..."
    FileUtils.mkdir_p @dir unless File.exists? @dir
    SourceManager.save_sources
    save_index
  end

  def load_index
    unimplemented
  end

  ## Syncs the message to the index, replacing any previous version.  adding
  ## either way. Index state will be determined by the message's #labels
  ## accessor.
  def sync_message m, opts={}
    unimplemented
  end

  def save_index fn
    unimplemented
  end

  def contains_id? id
    unimplemented
  end

  def contains? m; contains_id? m.id end

  def size
    unimplemented
  end

  def empty?; size == 0 end

  ## Yields a message-id and message-building lambda for each
  ## message that matches the given query, in descending date order.
  ## You should probably not call this on a block that doesn't break
  ## rather quickly because the results can be very large.
  def each_id_by_date query={}
    unimplemented
  end

  ## Return the number of matches for query in the index
  def num_results_for query={}
    unimplemented
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
    unimplemented
  end

  ## Load message with the given message-id from the index
  def build_message id
    unimplemented
  end

  ## Delete message with the given message-id from the index
  def delete id
    unimplemented
  end

  ## Given an array of email addresses, return an array of Person objects that
  ## have sent mail to or received mail from any of the given addresses.
  def load_contacts email_addresses, h={}
    unimplemented
  end

  ## Yield each message-id matching query
  def each_id query={}
    unimplemented
  end

  ## Yield each message matching query
  def each_message query={}, &b
    each_id query do |id|
      yield build_message(id)
    end
  end

  ## Implementation-specific optimization step
  def optimize
    unimplemented
  end

  ## Return the id source of the source the message with the given message-id
  ## was synced from
  def source_for_id id
    unimplemented
  end

  class ParseError < StandardError; end

  ## parse a query string from the user. returns a query object
  ## that can be passed to any index method with a 'query'
  ## argument.
  ##
  ## raises a ParseError if something went wrong.
  def parse_query s
    unimplemented
  end
end

index_name = ENV['SUP_INDEX'] || $config[:index] || DEFAULT_INDEX
case index_name
  when "xapian"; require "sup/xapian_index"
  when "ferret"; require "sup/ferret_index"
  else fail "unknown index type #{index_name.inspect}"
end
Index = Redwood.const_get "#{index_name.capitalize}Index"
Redwood::log "using index #{Index.name}"

end
