module Redwood

class LabelSearchResultsMode < ThreadIndexMode
  def initialize labels
    @labels = labels
    super
  end

  def is_relevant? m; @labels.all? { |l| m.has_label? l }; end

  def load_threads opts={}
    n = opts[:num] || ThreadIndexMode::LOAD_MORE_THREAD_NUM
    load_n_threads_background n, :labels => @labels,
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
