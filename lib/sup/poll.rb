require 'thread'

module Redwood

class PollManager
  include Singleton

  DELAY = 300

  def initialize
    @mutex = Mutex.new
    @last_poll = nil
    
    self.class.i_am_the_instance self
  end

  def buffer
    BufferManager.spawn_unless_exists("<poll for new messages>", :hidden => true) { PollMode.new }
  end

  def poll
    BufferManager.flash "Polling for new messages..."
    num, numi = buffer.mode.poll
    if num > 0
      BufferManager.flash "Loaded #{num} new messages, #{numi} to inbox." 
    else
      BufferManager.flash "No new messages." 
    end
    [num, numi]
  end

  def start_thread
    Redwood::reporting_thread do
      while true
        sleep DELAY / 2
        poll if @last_poll.nil? || (Time.now - @last_poll) >= DELAY
      end
    end
  end

  def do_poll
    total_num = total_numi = 0
    @mutex.synchronize do
      Index.usual_sources.each do |source|
#        yield "source #{source} is done? #{source.done?} (cur_offset #{source.cur_offset} >= #{source.end_offset})"
        begin
          yield "Loading from #{source}... " unless source.done? || source.has_errors?
        rescue SourceError => e
          Redwood::log "problem getting messages from #{source}: #{e.message}"
          Redwood::report_broken_sources
          next
        end

        num = 0
        numi = 0
        add_messages_from source do |m, offset, entry|
          ## always preserve the labels on disk.
          m.labels = entry[:label].split(/\s+/).map { |x| x.intern } if entry
          yield "Found message at #{offset} with labels {#{m.labels * ', '}}"
          unless entry
            num += 1
            numi += 1 if m.labels.include? :inbox
          end
          m
        end
        yield "Found #{num} messages, #{numi} to inbox" unless num == 0
        total_num += num
        total_numi += numi
      end

      yield "Done polling; loaded #{total_num} new messages total"
      @last_poll = Time.now
      @polling = false
    end
    [total_num, total_numi]
  end

  ## this is the main mechanism for adding new messages to the
  ## index. it's called both by sup-sync and by PollMode.
  ##
  ## for each message in the source, starting from the source's
  ## starting offset, this methods yields the message, the source
  ## offset, and the index entry on disk (if any). it expects the
  ## yield to return the message (possibly altered in some way), and
  ## then adds it (if new) or updates it (if previously seen).
  ##
  ## the labels of the yielded message are the default source
  ## labels. it is likely that callers will want to replace these with
  ## the index labels, if they exist, so that state is not lost when
  ## e.g. a new version of a message from a mailing list comes in.
  def add_messages_from source
    begin
      return if source.done? || source.has_errors?
      
      source.each do |offset, labels|
        if source.has_errors?
          Redwood::log "error loading messages from #{source}: #{source.error.message}"
          return
        end
      
        labels.each { |l| LabelManager << l }
        labels = labels + (source.archived? ? [] : [:inbox])

        begin
          m = Message.new :source => source, :source_info => offset, :labels => labels
          if m.source_marked_read?
            m.remove_label :unread
            labels.delete :unread
          else
            m.add_label :unread
            labels << :unread
          end

          docid, entry = Index.load_entry_for_id m.id
          m = yield(m, offset, entry) or next
          Index.sync_message m, docid, entry
          UpdateManager.relay self, :add, m unless entry
        rescue MessageFormatError => e
          Redwood::log "ignoring erroneous message at #{source}##{offset}: #{e.message}"
        end
      end
    rescue SourceError => e
      Redwood::log "problem getting messages from #{source}: #{e.message}"
      Redwood::report_broken_sources
    end
  end
end

end
