module Redwood

class SuicideManager
  include Singleton

  DELAY = 5

  def initialize fn
    @fn = fn
    @die = false
    self.class.i_am_the_instance self
    FileUtils.rm_f @fn
  end

  bool_reader :die

  def start_thread
    Redwood::reporting_thread do
      while true
        sleep DELAY
        if File.exists? @fn
          FileUtils.rm_f @fn
          @die = true
        end
      end
    end
  end
end

end
