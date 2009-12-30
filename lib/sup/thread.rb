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
## determined by the references: and in-reply-to: headers. Each
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

require 'set'

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
    f.puts "=== start thread with #{@containers.length} trees ==="
    @containers.each { |c| c.dump_recursive f; f.puts }
    f.puts "=== end thread ==="
  end

  ## yields each message, its depth, and its parent. the message yield
  ## parameter can be a Message object, or :fake_root, or nil (no
  ## message found but the presence of one deduced from other
  ## messages).
  def each fake_root=false
    adj = 0
    root = @containers.find_all { |c| c.message && !Message.subj_is_reply?(c.message.subj) }.argmin { |c| c.date }

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
  def snippet
    with_snippets = select { |m, *o| m && m.snippet && !m.snippet.empty? }
    first_unread, * = with_snippets.select { |m, *o| m.has_label?(:unread) }.sort_by { |m, *o| m.date }.first
    return first_unread.snippet if first_unread
    last_read, * = with_snippets.sort_by { |m, *o| m.date }.last
    return last_read.snippet if last_read
    ""
  end
  def authors; map { |m, *o| m.from if m }.compact.uniq; end

  def apply_label t; each { |m, *o| m && m.add_label(t) }; end
  def remove_label t; each { |m, *o| m && m.remove_label(t) }; end

  def toggle_label label
    if has_label? label
      remove_label label
      false
    else
      apply_label label
      true
    end
  end

  def set_labels l; each { |m, *o| m && m.labels = l }; end
  def has_label? t; any? { |m, *o| m && m.has_label?(t) }; end
  def each_dirty_message; each { |m, *o| m && m.dirty? && yield(m) }; end

  def direct_participants
    map { |m, *o| [m.from] + m.to if m }.flatten.compact.uniq
  end

  def participants
    map { |m, *o| [m.from] + m.to + m.cc + m.bcc if m }.flatten.compact.uniq
  end

  def size; map { |m, *o| m ? 1 : 0 }.sum; end
  def subj; argfind { |m, *o| m && m.subj }; end
  def labels; inject(Set.new) { |s, (m, *o)| m ? s | m.labels : s } end
  def labels= l
    raise ArgumentError, "not a set" unless l.is_a?(Set)
    each { |m, *o| m && m.labels = l.dup }
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

  ## skip over any containers which are empty and have only one child. we use
  ## this make the threaded display a little nicer, and only stick in the
  ## "missing message" line when it's graphically necessary, i.e. when the
  ## missing message has more than one descendent.
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

  def is_reply?; subj && Message.subj_is_reply?(subj); end

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
    line = "[#{thread.nil? ? ' ' : '*'}] " + #"[#{useful? ? 'U' : ' '}] " +
      if @message
        message.subj ##{@message.refs.inspect} / #{@message.replytos.inspect}"
      else
        "<no message>"
      end

    f.puts "#{id} #{line}"#[0 .. (105 - indent)]
    indent += 3
    @children.each { |c| c.dump_recursive f, indent, false, self }
  end
end

## A set of threads, so a forest. Is integrated with the index and
## builds thread structures by reading messages from it.
##
## If 'thread_by_subj' is true, puts messages with the same subject in
## one thread, even if they don't reference each other. This is
## helpful for crappy MUAs that don't set In-reply-to: or References:
## headers, but means that messages may be threaded unnecessarily.
##
## The following invariants are maintained: every Thread has at least one
## Container tree, and every Container tree has at least one Message.
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

  def thread_for_id mid; @messages.member?(mid) && @messages[mid].root.thread end
  def contains_id? id; @messages.member?(id) && !@messages[id].empty? end
  def thread_for m; thread_for_id m.id end
  def contains? m; contains_id? m.id end

  def threads; @threads.values end
  def size; @threads.size end

  def dump f=$stdout
    @threads.each do |s, t|
      f.puts "**********************"
      f.puts "** for subject #{s} **"
      f.puts "**********************"
      t.dump f
    end
  end

  ## link two containers
  def link p, c, overwrite=false
    if p == c || p.descendant_of?(c) || c.descendant_of?(p) # would create a loop
      #puts "*** linking parent #{p.id} and child #{c.id} would create a loop"
      return
    end

    #puts "in link for #{p.id} to #{c.id}, perform? #{c.parent.nil?} || #{overwrite}"

    return unless c.parent.nil? || overwrite
    remove_container c
    p.children << c
    c.parent = p

    ## if the child was previously a top-level container, it now ain't,
    ## so ditch our thread and kill it if necessary
    prune_thread_of c
  end
  private :link

  def remove_container c
    c.parent.children.delete c if c.parent # remove from tree
  end
  private :remove_container

  def prune_thread_of c
    return unless c.thread
    c.thread.drop c
    @threads.delete_if { |k, v| v == c.thread } if c.thread.empty?
    c.thread = nil
  end
  private :prune_thread_of

  def remove_id mid
    return unless @messages.member?(mid)
    c = @messages[mid]
    remove_container c
    prune_thread_of c
  end

  def remove_thread_containing_id mid
    return unless @messages.member?(mid)
    c = @messages[mid]
    t = c.root.thread
    @threads.delete_if { |key, thread| t == thread }
  end

  ## load in (at most) num number of threads from the index
  def load_n_threads num, opts={}
    @index.each_id_by_date opts do |mid, builder|
      break if size >= num unless num == -1
      next if contains_id? mid

      m = builder.call
      load_thread_for_message m, :skip_killed => opts[:skip_killed], :load_deleted => opts[:load_deleted], :load_spam => opts[:load_spam]
      yield size if block_given?
    end
  end

  ## loads in all messages needed to thread m
  ## may do nothing if m's thread is killed
  def load_thread_for_message m, opts={}
    good = @index.each_message_in_thread_for m, opts do |mid, builder|
      next if contains_id? mid
      add_message builder.call
    end
    add_message m if good
  end

  ## merges in a pre-loaded thread
  def add_thread t
    raise "duplicate" if @threads.values.member? t
    t.each { |m, *o| add_message m }
  end

  ## merges two threads together. both must be members of this threadset.
  ## does its best, heuristically, to determine which is the parent.
  def join_threads threads
    return if threads.size < 2

    containers = threads.map do |t|
      c = @messages.member?(t.first.id) ? @messages[t.first.id] : nil
      raise "not in threadset: #{t.first.id}" unless c && c.message
      c
    end

    ## use subject headers heuristically
    parent = containers.find { |c| !c.is_reply? }

    ## no thread was rooted by a non-reply, so make a fake parent
    parent ||= @messages["joining-ref-" + containers.map { |c| c.id }.join("-")]

    containers.each do |c|
      next if c == parent
      c.message.add_ref parent.id
      link parent, c
    end

    true
  end

  def is_relevant? m
    m.refs.any? { |ref_id| @messages.member? ref_id }
  end

  ## the heart of the threading code
  def add_message message
    el = @messages[message.id]
    return if el.message # we've seen it before

    #puts "adding: #{message.id}, refs #{message.refs.inspect}"

    el.message = message
    oldroot = el.root

    ## link via references:
    (message.refs + [el.id]).inject(nil) do |prev, ref_id|
      ref = @messages[ref_id]
      link prev, ref if prev
      ref
    end

    ## link via in-reply-to:
    message.replytos.each do |ref_id|
      ref = @messages[ref_id]
      link ref, el, true
      break # only do the first one
    end

    root = el.root
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
      if @threads.member?(key) && @threads[key] != root.thread
        @threads.delete key
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
