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
num_inbox_total_unread: the total number of unread messages in the inbox
         from_and_subj: an array of (from email address, subject) pairs
   from_and_subj_inbox: an array of (from email address, subject) pairs for
                        only those messages appearing in the inbox
EOS

  DELAY = 300

  def initialize
    @mutex = Mutex.new
    @thread = nil
    @last_poll = nil
    @polling = false
    @poll_sources = nil
    @mode = nil
  end

  def poll_with_sources
    @mode ||= PollMode.new
    HookManager.run "before-poll"

    BufferManager.flash "Polling for new messages..."
    num, numi, from_and_subj, from_and_subj_inbox, loaded_labels = @mode.poll
    if num > 0
      BufferManager.flash "Loaded #{num.pluralize 'new message'}, #{numi} to inbox. Labels: #{loaded_labels.map{|l| l.to_s}.join(', ')}"
    else
      BufferManager.flash "No new messages." 
    end

    HookManager.run "after-poll", :num => num, :num_inbox => numi, :from_and_subj => from_and_subj, :from_and_subj_inbox => from_and_subj_inbox, :num_inbox_total_unread => lambda { Index.num_results_for :labels => [:inbox, :unread] }

  end

  def poll
    return if @polling
    @polling = true
    @poll_sources = SourceManager.usual_sources
    num, numi = poll_with_sources
    @polling = false
    [num, numi]
  end

  def poll_unusual
    return if @polling
    @polling = true
    @poll_sources = SourceManager.unusual_sources
    num, numi = poll_with_sources
    @polling = false
    [num, numi]
  end

  def start
    @thread = Redwood::reporting_thread("periodic poll") do
      while true
        sleep DELAY / 2
        poll if @last_poll.nil? || (Time.now - @last_poll) >= DELAY
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
#        yield "source #{source} is done? #{source.done?} (cur_offset #{source.cur_offset} >= #{source.end_offset})"
        begin
          yield "Loading from #{source}... " unless source.done? || (source.respond_to?(:has_errors?) && source.has_errors?)
        rescue SourceError => e
          warn "problem getting messages from #{source}: #{e.message}"
          Redwood::report_broken_sources :force_to_top => true
          next
        end

        num = 0
        numi = 0
        each_message_from source do |m|
          old_m = Index.build_message m.id
          if old_m
              if old_m.source.id != source.id || old_m.source_info != m.source_info
              ## here we merge labels between new and old versions, but we don't let the new
              ## message add :unread or :inbox labels. (they can exist in the old version,
              ## just not be added.)
              new_labels = old_m.labels + (m.labels - [:unread, :inbox])
              yield "Message at #{m.source_info} is an updated of an old message. Updating labels from #{m.labels.to_a * ','} => #{new_labels.to_a * ','}"
              m.labels = new_labels
              Index.update_message m
            else
              yield "Skipping already-imported message at #{m.source_info}"
            end
          else
            yield "Found new message at #{m.source_info} with labels #{m.labels.to_a * ','}"
            add_new_message m
            loaded_labels.merge m.labels
            num += 1
            from_and_subj << [m.from && m.from.longname, m.subj]
            if (m.labels & [:inbox, :spam, :deleted, :killed]) == Set.new([:inbox])
              from_and_subj_inbox << [m.from && m.from.longname, m.subj]
              numi += 1
            end
          end
          m
        end
        yield "Found #{num} messages, #{numi} to inbox." unless num == 0
        total_num += num
        total_numi += numi
      end

      loaded_labels = loaded_labels - LabelManager::HIDDEN_RESERVED_LABELS - [:inbox, :killed]
      yield "Done polling; loaded #{total_num} new messages total"
      @last_poll = Time.now
      @polling = false
    end
    [total_num, total_numi, from_and_subj, from_and_subj_inbox, loaded_labels]
  end

  ## like Source#each, but yields successive Message objects, which have their
  ## labels and offsets set correctly.
  ##
  ## this is the primary mechanism for iterating over messages from a source.
  def each_message_from source, opts={}
    begin
      return if source.done? || source.has_errors?

      source.each do |offset, source_labels|
        if source.has_errors?
          warn "error loading messages from #{source}: #{source.error.message}"
          return
        end

        m = Message.build_from_source source, offset
        m.labels += source_labels + (source.archived? ? [] : [:inbox])
        m.labels.delete :unread if m.source_marked_read? # preserve read status if possible
        m.labels.each { |l| LabelManager << l }

        HookManager.run "before-add-message", :message => m
        yield m
      end
    rescue SourceError => e
      warn "problem getting messages from #{source}: #{e.message}"
      Redwood::report_broken_sources :force_to_top => true
    end
  end

  ## TODO: see if we can do this within PollMode rather than by calling this
  ## method.
  ##
  ## a wrapper around Index.add_message that calls the proper hooks,
  ## does the gui callback stuff, etc.
  def add_new_message m
    Index.add_message m
    UpdateManager.relay self, :added, m
  end
end

end
