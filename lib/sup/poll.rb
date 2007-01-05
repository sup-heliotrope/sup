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

  ## TODO: merge this with sup-import
  def do_poll
    total_num = total_numi = 0
    @mutex.synchronize do
      found = {}
      Index.usual_sources.each do |source|
        next if source.broken? || source.done?

        yield "Loading from #{source}... "
        start_offset = nil
        num = 0
        num_inbox = 0

        source.each do |offset, labels|
          break if source.broken?
          start_offset ||= offset
          yield "Found message at #{offset} with labels #{labels * ', '}"

          begin
            begin
              m = Redwood::Message.new :source => source, :source_info => offset, :labels => labels
            rescue MessageFormatError => e
              yield "Non-fatal error loading message #{source}##{offset}: #{e.message}"
              next
            end

            if found[m.id]
              yield "Skipping duplicate message #{m.id}"
              next
            end
            found[m.id] = true
          
            if Index.add_message m
              UpdateManager.relay :add, m
              num += 1
              total_num += 1
              total_numi += 1 if m.labels.include? :inbox
            end
        
            if num % 1000 == 0 && num > 0
              elapsed = Time.now - start
              pctdone = source.pct_done
              remaining = (100.0 - pctdone) * (elapsed.to_f / pctdone)
              yield "## #{num} (#{pctdone}% done) read; #{elapsed.to_time_s} elapsed; est. #{remaining.to_time_s} remaining"
            end
          rescue SourceError => e
            msg = "Fatal error loading from #{source}: #{e.message}"
            Redwood::log msg
            yield msg
            break
          end
        end
        yield "Found #{num} messages" unless num == 0
      end

      yield "Done polling; loaded #{total_num} new messages total"
      @last_poll = Time.now
      @polling = false
    end
    [total_num, total_numi]
  end
end

end
