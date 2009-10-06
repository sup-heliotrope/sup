module Redwood

class PollMode < LogMode
  include M17n

  def initialize
    @new = true
    super m('poll.poll_for_new_messages')
  end

  def poll
    unless @new
      @new = false
      self << "\n"
    end
    self << "#{m('poll.started_at', :time => Time.now)}\n"
    PollManager.do_poll { |s| self << (s + "\n") }
  end
end

end
