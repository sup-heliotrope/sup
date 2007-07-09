module Redwood

class LabelManager
  include Singleton

  ## labels that have special semantics. user will be unable to
  ## add/remove these via normal label mechanisms.
  RESERVED_LABELS = [ :starred, :spam, :draft, :unread, :killed, :sent, :deleted ]

  ## labels which it nonetheless makes sense to search for by
  LISTABLE_RESERVED_LABELS = [ :starred, :spam, :draft, :sent, :killed, :deleted ]

  ## labels that will never be displayed to the user
  HIDDEN_RESERVED_LABELS = [ :starred, :unread ]

  def initialize fn
    @fn = fn
    labels = 
      if File.exists? fn
        IO.readlines(fn).map { |x| x.chomp.intern }
      else
        []
      end
    @labels = {}
    @modified = false
    labels.each { |t| @labels[t] = true }

    self.class.i_am_the_instance self
  end

  ## all listable (user-defined and system listable) labels, ordered
  ## nicely and converted to pretty strings. use #label_for to recover
  ## the original label.
  def listable_label_strings
    LISTABLE_RESERVED_LABELS.sort_by { |l| l.to_s }.map { |l| l.to_s.ucfirst } +
      @labels.keys.map { |l| l.to_s }.sort
  end

  ## reverse the label->string mapping, for convenience!
  def label_for string
    string.downcase.intern
  end
  
  def << t
    unless @labels.member?(t) || RESERVED_LABELS.member?(t)
      @labels[t] = true
      @modified = true
    end
  end

  def delete t
    if @labels.delete t
      @modified = true
    end
  end

  def save
    return unless @modified
    File.open(@fn, "w") { |f| f.puts @labels.keys }
  end
end

end
