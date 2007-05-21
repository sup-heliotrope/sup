module Redwood

class SearchResultsMode < ThreadIndexMode
  def initialize qobj
    @qobj = qobj
    super
  end

  ## TODO: think about this
  def is_relevant? m; super; end

  def load_threads opts={}
    n = opts[:num] || ThreadIndexMode::LOAD_MORE_THREAD_NUM
    load_n_threads_background n, :qobj => @qobj,
                                 :load_killed => true,
                                 :load_spam => false,
                                 :when_done =>(lambda do |num|
      opts[:when_done].call(num) if opts[:when_done]
      if num > 0
        BufferManager.flash "Found #{num} threads"
      else
        BufferManager.flash "No matches"
      end
    end)
  end
end

end
