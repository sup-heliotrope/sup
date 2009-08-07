module Redwood

class SuicideManager
  include Singleton

  DELAY = 5

  def initialize fn
    @fn = fn
    @die = false
    @thread = nil
    self.class.i_am_the_instance self
    FileUtils.rm_f @fn
  end

  bool_reader :die
  def please_die!; @die = true end

  def start
    @thread = Redwood::reporting_thread("suicide watch") do
      while true
        sleep DELAY
        if File.exists? @fn
          FileUtils.rm_f @fn
          @die = true
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
