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
      found = {}
      Index.usual_sources.each do |source|
        yield "Loading from #{source}... " unless source.done? || source.broken?
        num = 0
        numi = 0
        Index.add_new_messages_from source do |m, offset, source_labels, entry|
          yield "Found message at #{offset} with labels #{m.labels * ', '}"
          num += 1
          numi += 1 if m.labels.include? :inbox
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
end

end
