module Redwood

class PollMode < LogMode
  def initialize
    @new = true
    super I18n['poll.poll_for_new_messages']
  end

  def poll
    unless @new
      @new = false
      self << "\n"
    end
    self << "#{I18n['poll.started_at', {:TIME => Time.now}]}\n"
    PollManager.do_poll { |s| self << (s + "\n") }
  end
end

end
