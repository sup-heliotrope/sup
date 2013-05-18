module Redwood

class PollMode < LogMode
  def initialize
    @new = true
    super "poll for new messages"
  end

  def poll
    unless @new
      @new = false
      self << "\n"
    end
    self << "Poll started at #{Time.now}\n"
    PollManager.do_poll { |s| self << (s + "\n") }
  end
end

end
