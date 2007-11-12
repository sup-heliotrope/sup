module Redwood

class PollMode < LogMode
  def initialize
    @new = true
    super
  end

  def puts s=""
    self << s + "\n"
  end

  def poll
    puts unless @new
    @new = false
    puts "Poll started at #{Time.now}"
    PollManager.do_poll { |s| puts s }
  end
end

end
