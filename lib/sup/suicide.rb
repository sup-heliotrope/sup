require 'fileutils'
module Redwood

class SuicideException < StandardError; end

class SuicideManager
  include Singleton

  DELAY = 5

  def initialize fn
    @fn = fn
    self.class.i_am_the_instance self
  end

  def start_thread
    Redwood::reporting_thread do
      while true
        sleep DELAY
        if File.exists? @fn
          FileUtils.rm_rf @fn
          raise SuicideException
        end
      end
    end
  end
end

end
