module Redwood

class LabelManager
  include Singleton

  ## labels that have special semantics. user will be unable to
  ## add/remove these via normal label mechanisms.
  RESERVED_LABELS = [ :starred, :spam, :draft, :unread, :killed, :sent, :deleted ]

  ## labels which it nonetheless makes sense to search for by
  LISTABLE_LABELS = [ :starred, :spam, :draft, :sent, :killed, :deleted ]

  ## labels that will never be displayed to the user
  HIDDEN_LABELS = [ :starred, :unread ]

  def initialize fn
    @fn = fn
    labels = 
      if File.exists? fn
        IO.readlines(fn).map { |x| x.chomp.intern }
      else
        []
      end
    @labels = {}
    labels.each { |t| @labels[t] = true }

    self.class.i_am_the_instance self
  end

  def user_labels; @labels.keys; end
  def << t; @labels[t] = true unless @labels.member?(t) || RESERVED_LABELS.member?(t); end
  def delete t; @labels.delete t; end
  def save
    File.open(@fn, "w") { |f| f.puts @labels.keys }
  end
end

end
