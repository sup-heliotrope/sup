# encoding: utf-8

module Redwood

class LabelManager
  include Redwood::Singleton

  ## labels that have special semantics. user will be unable to
  ## add/remove these via normal label mechanisms.
  RESERVED_LABELS = [ :starred, :spam, :draft, :unread, :killed, :sent, :deleted, :inbox, :attachment, :forwarded, :replied ]

  ## labels that will typically be hidden from the user
  HIDDEN_RESERVED_LABELS = [ :starred, :unread, :attachment, :forwarded, :replied ]

  def initialize fn
    @fn = fn
    labels =
      if File.exist? fn
        IO.readlines(fn).map { |x| x.chomp.intern }
      else
        []
      end
    @labels = {}
    @new_labels = {}
    @modified = false
    labels.each { |t| @labels[t] = true }
  end

  def new_label? l; @new_labels.include?(l) end

  ## all labels user-defined and system, ordered
  ## nicely and converted to pretty strings. use #label_for to recover
  ## the original label.
  def all_labels
    ## uniq's only necessary here because of certain upgrade issues
    (RESERVED_LABELS + @labels.keys).uniq
  end

  ## all user-defined labels, ordered
  ## nicely and converted to pretty strings. use #label_for to recover
  ## the original label.
  def user_defined_labels
    @labels.keys
  end

  ## reverse the label->string mapping, for convenience!
  def string_for l
    if RESERVED_LABELS.include? l
      l.to_s.capitalize
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
    raise ArgumentError, "expecting a symbol" unless t.is_a? Symbol
    unless @labels.member?(t) || RESERVED_LABELS.member?(t)
      @labels[t] = true
      @new_labels[t] = true
      @modified = true
    end
  end

  def delete t
    if @labels.delete(t)
      @modified = true
    end
  end

  def save
    return unless @modified
    File.open(@fn, "w:UTF-8") { |f| f.puts @labels.keys.sort_by { |l| l.to_s } }
    @new_labels = {}
  end
end

end
