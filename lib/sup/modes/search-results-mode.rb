module Redwood

class SearchResultsMode < ThreadIndexMode
  register_keymap do |k|
    k.add :load_more_threads, "Load #{LOAD_MORE_THREAD_NUM} more threads", 'M'
  end

  def initialize content
    raise ArgumentError, "no content" if content =~ /^\s*$/
    @content = content.gsub(/[\(\)]/) { |x| "\\" + x }
    super
  end

  ## TODO: think about this
  def is_relevant? m; super; end

  def load_more_threads n=ThreadIndexMode::LOAD_MORE_THREAD_NUM
    load_n_threads_background n, :content => @content,
                                 :load_killed => true,
                                 :load_spam => false,
                                 :when_done =>(lambda do |num|
      if num > 0
        BufferManager.flash "Found #{num} threads"
      else
        BufferManager.flash "No matches"
      end
    end)
  end
end

end
