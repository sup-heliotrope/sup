## Herein lies all the code responsible for threading messages. It's
## basically an online version of the JWZ threading algorithm:
## http://www.jwz.org/doc/threading.html
##
## I didn't implement it for efficiency, but thanks to our search
## engine backend, it's typically not applied to very many messages at
## once.
##
## At the top level, we have a ThreadSet, which represents a set of
## threads, e.g. a message folder or an inbox. Each ThreadSet contains
## zero or more Threads. A Thread represents all the message related
## to a particular subject. Each Thread has one or more Containers.  A
## Container is a recursive structure that holds the message tree as
## determined by the references: and in-reply-to: headers. EAch
## Container holds zero or one messages. In the case of zero messages,
## it means we've seen a reference to the message but haven't (yet)
## seen the message itself.
##
## A Thread can have multiple top-level Containers if we decide to
## group them together independent of tree structure, typically if
## (e.g. due to someone using a primitive MUA) the messages have the
## same subject but we don't have evidence from in-reply-to: or
## references: headers. In this case Thread#each can optionally yield
## a faked root object tying them all together into one tree
## structure.

module Redwood

class Thread
  include Enumerable

  attr_reader :containers
  def initialize
    ## ah, the joys of a multithreaded application with a class called
    ## "Thread". i keep instantiating the wrong one...
    raise "wrong Thread class, buddy!" if block_given?
    @containers = []
  end

  def << c
    @containers << c
  end

  def empty?; @containers.empty?; end
  def empty!; @containers.clear; end
  def drop c; @containers.delete(c) or raise "bad drop"; end

  ## unused
  def dump f=$stdout
    f.puts "=== start thread #{self} with #{@containers.length} trees ==="
    @containers.each { |c| c.dump_recursive f }
    f.puts "=== end thread ==="
  end

  ## yields each message, its depth, and its parent. the message yield
  ## parameter can be a Message object, or :fake_root, or nil (no
  ## message found but the presence of one induced from other
  ## messages).
  def each fake_root=false
    adj = 0
    root = @containers.find_all { |c| !Message.subj_is_reply?(c) }.argmin { |c| c.date || 0 }

    if root
      adj = 1
      root.first_useful_descendant.each_with_stuff do |c, d, par|
        yield c.message, d, (par ? par.message : nil)
      end
    elsif @containers.length > 1 && fake_root
      adj = 1
      yield :fake_root, 0, nil
    end

    @containers.each do |cont|
      next if cont == root
      fud = cont.first_useful_descendant
      fud.each_with_stuff do |c, d, par|
        ## special case here: if we're an empty root that's already
        ## been joined by a fake root, don't emit
        yield c.message, d + adj, (par ? par.message : nil) unless
          fake_root && c.message.nil? && root.nil? && c == fud 
      end
    end
  end

  def first; each { |m, *o| return m if m }; nil; end
  def dirty?; any? { |m, *o| m && m.dirty? }; end
  def date; map { |m, *o| m.date if m }.compact.max; end
  def snippet; argfind { |m, *o| m && m.snippet }; end
  def authors; map { |m, *o| m.from if m }.compact.uniq; end

  def apply_label t; each { |m, *o| m && m.add_label(t) }; end
  def remove_label t; each { |m, *o| m && m.remove_label(t) }; end

  def toggle_label label
    if has_label? label
      remove_label label
      return false
    else
      apply_label label
      return true
    end
  end

  def set_labels l; each { |m, *o| m && m.labels = l }; end
  
  def has_label? t; any? { |m, *o| m && m.has_label?(t) }; end
  def save index; each { |m, *o| m && m.save(index) }; end

  def direct_participants
    map { |m, *o| [m.from] + m.to if m }.flatten.compact.uniq
  end

  def participants
    map { |m, *o| [m.from] + m.to + m.cc + m.bcc if m }.flatten.compact.uniq
  end

  def size; map { |m, *o| m ? 1 : 0 }.sum; end
  def subj; argfind { |m, *o| m && m.subj }; end
  def labels
      map { |m, *o| m && m.labels }.flatten.compact.uniq.sort_by { |t| t.to_s }
  end
  def labels= l
    each { |m, *o| m && m.labels = l.clone }
  end

  def latest_message
    inject(nil) do |a, b| 
      b = b.first
      if a.nil?
        b
      elsif b.nil?
        a
      else
        b.date > a.date ? b : a
      end
    end
  end

  def to_s
    "<thread containing: #{@containers.join ', '}>"
  end
end

## recursive structure used internally to represent message trees as
## described by reply-to: and references: headers.
##
## the 'id' field is the same as the message id. but the message might
## be empty, in the case that we represent a message that was referenced
## by another message (as an ancestor) but never received.
class Container
  attr_accessor :message, :parent, :children, :id, :thread

  def initialize id
    raise "non-String #{id.inspect}" unless id.is_a? String
    @id = id
    @message, @parent, @thread = nil, nil, nil
    @children = []
  end      

  def each_with_stuff parent=nil
    yield self, 0, parent
    @children.each do |c|
      c.each_with_stuff(self) { |cc, d, par| yield cc, d + 1, par }
    end
  end

  def descendant_of? o
    if o == self
      true
    else
      @parent && @parent.descendant_of?(o)
    end
  end

  def == o; Container === o && id == o.id; end

  def empty?; @message.nil?; end
  def root?; @parent.nil?; end
  def root; root? ? self : @parent.root; end

  def first_useful_descendant
    if empty? && @children.size == 1
      @children.first.first_useful_descendant
    else
      self
    end
  end

  def find_attr attr
    if empty?
      @children.argfind { |c| c.find_attr attr }
    else
      @message.send attr
    end
  end
  def subj; find_attr :subj; end
  def date; find_attr :date; end

  def is_reply?; subj && Message.subject_is_reply?(subj); end

  def to_s
    [ "<#{id}",
      (@parent.nil? ? nil : "parent=#{@parent.id}"),
      (@children.empty? ? nil : "children=#{@children.map { |c| c.id }.inspect}"),
    ].compact.join(" ") + ">"
  end

  def dump_recursive f=$stdout, indent=0, root=true, parent=nil
    raise "inconsistency" unless parent.nil? || parent.children.include?(self)
    unless root
      f.print " " * indent
      f.print "+->"
    end
    line = #"[#{useful? ? 'U' : ' '}] " +
      if @message
        "[#{thread}] #{@message.subj} " ##{@message.refs.inspect} / #{@message.replytos.inspect}"
      else
        "<no message>"
      end

    f.puts "#{id} #{line}"#[0 .. (105 - indent)]
    indent += 3
    @children.each { |c| c.dump_recursive f, indent, false, self }
  end
end

## A set of threads (so a forest). Builds thread structures by reading
## messages from an index.
##
## If 'thread_by_subj' is true, puts messages with the same subject in
## one thread, even if they don't reference each other. This is
## helpful for crappy MUAs that don't set In-reply-to: or References:
## headers, but means that messages may be threaded unnecessarily.
class ThreadSet
  attr_reader :num_messages
  bool_reader :thread_by_subj

  def initialize index, thread_by_subj=true
    @index = index
    @num_messages = 0
    ## map from message ids to container objects
    @messages = SavingHash.new { |id| Container.new id }
    ## map from subject strings or (or root message ids) to thread objects
    @threads = SavingHash.new { Thread.new }
    @thread_by_subj = thread_by_subj
  end

  def contains_id? id; @messages.member?(id) && !@messages[id].empty?; end
  def thread_for m
    (c = @messages[m.id]) && c.root.thread
  end

  def delete_cruft
    @threads.each { |k, v| @threads.delete(k) if v.empty? }
  end
  private :delete_cruft

  def threads; delete_cruft; @threads.values; end
  def size; delete_cruft; @threads.size; end

  ## unused
  def dump f
    @threads.each do |s, t|
      f.puts "**********************"
      f.puts "** for subject #{s} **"
      f.puts "**********************"
      t.dump f
    end
  end

  def link p, c, overwrite=false
    if p == c || p.descendant_of?(c) || c.descendant_of?(p) # would create a loop
#      puts "*** linking parent #{p} and child #{c} would create a loop"
      return
    end

    if c.parent.nil? || overwrite
      c.parent.children.delete c if overwrite && c.parent
      if c.thread
        c.thread.drop c 
        c.thread = nil
      end
      p.children << c
      c.parent = p
    end
  end
  private :link

  def remove mid
    return unless(c = @messages[mid])

    c.parent.children.delete c if c.parent
    if c.thread
      c.thread.drop c
      c.thread = nil
    end
  end

  ## load in (at most) num number of threads from the index
  def load_n_threads num, opts={}
    @index.each_id_by_date opts do |mid, builder|
      break if size >= num
      next if contains_id? mid

      m = builder.call
      add_message m
      load_thread_for_message m, :load_killed => opts[:load_killed]
      yield size if block_given?
    end
  end

  ## loads in all messages needed to thread m
  def load_thread_for_message m, opts={}
    @index.each_message_in_thread_for m, opts.merge({:limit => 100}) do |mid, builder|
      next if contains_id? mid
      add_message builder.call
    end
  end

  ## merges in a pre-loaded thread
  def add_thread t
    raise "duplicate" if @threads.values.member? t
    t.each { |m, *o| add_message m }
  end

  def is_relevant? m
    m.refs.any? { |ref_id| @messages.member? ref_id }
  end

  ## the heart of the threading code
  def add_message message
    el = @messages[message.id]
    return if el.message # we've seen it before

    el.message = message
    oldroot = el.root

    ## link via references:
    prev = nil
    message.refs.each do |ref_id|
      ref = @messages[ref_id]
      link prev, ref if prev
      prev = ref
    end
    link prev, el, true if prev

    ## link via in-reply-to:
    message.replytos.each do |ref_id|
      ref = @messages[ref_id]
      link ref, el, true
      break # only do the first one
    end

    root = el.root

    ## new root. need to drop old one and put this one in its place
    if root != oldroot && oldroot.thread
      oldroot.thread.drop oldroot
      oldroot.thread = nil
    end

    key =
      if thread_by_subj?
        Message.normalize_subj root.subj
      else
        root.id
      end

    ## check to see if the subject is still the same (in the case
    ## that we first added a child message with a different
    ## subject)
    if root.thread
      unless @threads[key] == root.thread
        if @threads[key]
          root.thread.empty!
          @threads[key] << root
          root.thread = @threads[key]
        else
          @threads[key] = root.thread
        end
      end
    else
      thread = @threads[key]
      thread << root
      root.thread = thread
    end

    ## last bit
    @num_messages += 1
  end
end

end
