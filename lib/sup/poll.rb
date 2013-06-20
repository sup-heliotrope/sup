require 'thread'

module Redwood

class PollManager
  include Singleton

  HookManager.register "before-add-message", <<EOS
Executes immediately before a message is added to the index.
Variables:
  message: the new message
EOS

  HookManager.register "before-poll", <<EOS
Executes immediately before a poll for new messages commences.
No variables.
EOS

  HookManager.register "after-poll", <<EOS
Executes immediately after a poll for new messages completes.
Variables:
                   num: the total number of new messages added in this poll
             num_inbox: the number of new messages added in this poll which
                        appear in the inbox (i.e. were not auto-archived).
             num_total: the total number of messages
       num_inbox_total: the total number of new messages in the inbox.
num_inbox_total_unread: the total number of unread messages in the inbox
         from_and_subj: an array of (from email address, subject) pairs
   from_and_subj_inbox: an array of (from email address, subject) pairs for
                        only those messages appearing in the inbox
EOS

  def initialize
    @delay = $config[:poll_interval] || 300
    @mutex = Mutex.new
    @thread = nil
    @last_poll = nil
    @polling = Mutex.new
    @poll_sources = nil
    @mode = nil
    @should_clear_running_totals = false
    clear_running_totals # defines @running_totals
    UpdateManager.register self
  end

  def poll_with_sources
    @mode ||= PollMode.new

    if HookManager.enabled? "before-poll"
      HookManager.run("before-poll")
    else
      BufferManager.flash "Polling for new messages..."
    end

    num, numi, from_and_subj, from_and_subj_inbox, loaded_labels = @mode.poll
    clear_running_totals if @should_clear_running_totals
    @running_totals[:num] += num
    @running_totals[:numi] += numi
    @running_totals[:loaded_labels] += loaded_labels || []


    if HookManager.enabled? "after-poll"
      hook_args = { :num => num, :num_inbox => numi,
                    :num_total => @running_totals[:num], :num_inbox_total => @running_totals[:numi],
                    :from_and_subj => from_and_subj, :from_and_subj_inbox => from_and_subj_inbox,
                    :num_inbox_total_unread => lambda { Index.num_results_for :labels => [:inbox, :unread] } }

      HookManager.run("after-poll", hook_args)
    else
      if @running_totals[:num] > 0
        BufferManager.flash "Loaded #{@running_totals[:num].pluralize 'new message'}, #{@running_totals[:numi]} to inbox. Labels: #{@running_totals[:loaded_labels].map{|l| l.to_s}.join(', ')}"
      else
        BufferManager.flash "No new messages."
      end
    end

  end

  def poll
    if @polling.try_lock
      @poll_sources = SourceManager.usual_sources
      num, numi = poll_with_sources
      @polling.unlock
      [num, numi]
    else
      debug "poll already in progress."
      return
    end
  end

  def poll_unusual
    if @polling.try_lock
      @poll_sources = SourceManager.unusual_sources
      num, numi = poll_with_sources
      @polling.unlock
      [num, numi]
    else
      debug "poll_unusual already in progress."
      return
    end
  end

  def start
    @thread = Redwood::reporting_thread("periodic poll") do
      while true
        sleep @delay / 2
        poll if @last_poll.nil? || (Time.now - @last_poll) >= @delay
      end
    end
  end

  def stop
    @thread.kill if @thread
    @thread = nil
  end

  def do_poll
    total_num = total_numi = 0
    from_and_subj = []
    from_and_subj_inbox = []
    loaded_labels = Set.new

    @mutex.synchronize do
      @poll_sources.each do |source|
        begin
          yield "Loading from #{source}... "
        rescue SourceError => e
          warn "problem getting messages from #{source}: #{e.message}"
          next
        end

        num = 0
        numi = 0
        poll_from source do |action,m,old_m,progress|
          if action == :delete
            yield "Deleting #{m.id}"
          elsif action == :add
            if old_m
              new_locations = (m.locations - old_m.locations)
              if not new_locations.empty?
                yield "Message at #{new_locations[0].info} is an update of an old message. Updating labels from #{old_m.labels.to_a * ','} => #{m.labels.to_a * ','}"
              else
                yield "Skipping already-imported message at #{m.locations[-1].info}"
              end
            else
              yield "Found new message at #{m.source_info} with labels #{m.labels.to_a * ','}"
              loaded_labels.merge m.labels
              num += 1
              from_and_subj << [m.from && m.from.longname, m.subj]
              if (m.labels & [:inbox, :spam, :deleted, :killed]) == Set.new([:inbox])
                from_and_subj_inbox << [m.from && m.from.longname, m.subj]
                numi += 1
              end
            end
          else fail
          end
        end
        yield "Found #{num} messages, #{numi} to inbox." unless num == 0
        total_num += num
        total_numi += numi
      end

      loaded_labels = loaded_labels - LabelManager::HIDDEN_RESERVED_LABELS - [:inbox, :killed]
      yield "Done polling; loaded #{total_num} new messages total"
      @last_poll = Time.now
    end
    [total_num, total_numi, from_and_subj, from_and_subj_inbox, loaded_labels]
  end

  ## like Source#poll, but yields successive Message objects, which have their
  ## labels and locations set correctly. The Messages are saved to or removed
  ## from the index after being yielded.
  def poll_from source, opts={}
    debug "trying to acquiring poll lock for: #{source}.."
    if source.poll_lock.try_lock
      debug "lock acquired for: #{source}."
      begin
        source.poll do |sym, args|
          case sym
          when :add
            m = Message.build_from_source source, args[:info]
            old_m = Index.build_message m.id
            m.labels += args[:labels]
            m.labels.delete :inbox  if source.archived?
            m.labels.delete :unread if source.read?
            m.labels.delete :unread if m.source_marked_read? # preserve read status if possible
            m.labels.each { |l| LabelManager << l }
            m.labels = old_m.labels + (m.labels - [:unread, :inbox]) if old_m
            m.locations = old_m.locations + m.locations if old_m
            HookManager.run "before-add-message", :message => m
            yield :add, m, old_m, args[:progress] if block_given?
            Index.sync_message m, true

            ## We need to add or unhide the message when it either did not exist
            ## before at all or when it was updated. We do *not* add/unhide when
            ## the same message was found at a different location
            if !old_m or not old_m.locations.member? m.location
              UpdateManager.relay self, :added, m
            end
          when :delete
            Index.each_message :location => [source.id, args[:info]] do |m|
              m.locations.delete Location.new(source, args[:info])
              yield :delete, m, [source,args[:info]], args[:progress] if block_given?
              Index.sync_message m, false
              #UpdateManager.relay self, :deleted, m
            end
          end
        end

      rescue SourceError => e
        warn "problem getting messages from #{source}: #{e.message}"

      ensure
        source.go_idle
        source.poll_lock.unlock
      end
    else
      debug "source #{source} is already being polled."
    end
  end

  def handle_idle_update sender, idle_since; @should_clear_running_totals = false; end
  def handle_unidle_update sender, idle_since; @should_clear_running_totals = true; clear_running_totals; end
  def clear_running_totals; @running_totals = {:num => 0, :numi => 0, :loaded_labels => Set.new}; end
end

end
