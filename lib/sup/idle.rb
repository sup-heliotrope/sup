require 'thread'

module Redwood

class IdleManager
  include Redwood::Singleton

  IDLE_THRESHOLD = 60

  def initialize
    @no_activity_since = Time.now
    @idle = false
    @thread = nil
  end

  def ping
    if @idle
      UpdateManager.relay self, :unidle, Time.at(@no_activity_since)
      @idle = false
    end
    @no_activity_since = Time.now
  end

  def start
    @thread = Redwood::reporting_thread("checking for idleness") do
      while true
        sleep 1
        if !@idle and Time.now.to_i - @no_activity_since.to_i >= IDLE_THRESHOLD
          UpdateManager.relay self, :idle, Time.at(@no_activity_since)
          @idle = true
        end
      end
    end
  end

  def stop
    @thread.kill if @thread
    @thread = nil
  end
end

end
