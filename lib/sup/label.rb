module Redwood

class LabelManager
  include Singleton

  ## labels that have special semantics. user will be unable to
  ## add/remove these via normal label mechanisms.
  RESERVED_LABELS = [ :starred, :spam, :draft, :unread, :killed, :sent, :deleted, :inbox ]

  ## labels which it nonetheless makes sense to search for by
  LISTABLE_RESERVED_LABELS = [ :starred, :spam, :draft, :sent, :killed, :deleted, :inbox ]

  ## labels that will typically be hidden from the user
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

  ## all listable (just user-defined at the moment) labels, ordered
  ## nicely and converted to pretty strings. use #label_for to recover
  ## the original label.
  def listable_labels
    LISTABLE_RESERVED_LABELS + @labels.keys
  end

  ## all apply-able (user-defined and system listable) labels, ordered
  ## nicely and converted to pretty strings. use #label_for to recover
  ## the original label.
  def applyable_labels
    @labels.keys
  end

  ## reverse the label->string mapping, for convenience!
  def string_for l
    if RESERVED_LABELS.include? l
      l.to_s.ucfirst
    else
      l.to_s
    end
  end

  def label_for s
    l = s.intern
    l2 = s.downcase.intern
    if RESERVED_LABELS.include? l2
      l2
    else
      l
    end
  end
  
  def << t
    t = t.intern unless t.is_a? Symbol
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
