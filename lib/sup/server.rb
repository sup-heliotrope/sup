require 'sup/protocol'

module Redwood

class Server < EM::P::RedwoodServer
  def initialize index
    super
    @index = index
  end

  def receive_message type, tag, params
    if respond_to? :"request_#{type}"
      send :"request_#{type}", tag, params
    else
      send_message 'error', tag, 'description' => "invalid request type #{type.inspect}"
    end
  end

  def request_query tag, a
    q = @index.parse_query a['query']
    query q, a['offset'], a['limit'], a['raw'] do |r|
      send_message 'message', tag, r
    end
    send_message 'done', tag
  end

  def request_count tag, a
    q = @index.parse_query a['query']
    c = count q
    send_message 'count', tag, 'count' => c
  end

  def request_label tag, a
    q = @index.parse_query a['query']
    label q, a['add'], a['remove']
    send_message 'done', tag
  end

  def request_add tag, a
    add a['raw'], a['labels']
    send_message 'done', tag
  end

  def request_thread tag, a
    thread a['message_id'], a['raw'] do |r|
      send_message 'message', tag, r
    end
    send_message 'done', tag
  end

private

  def result_from_message m, raw
    mkperson = lambda { |p| { :email => p.email, :name => p.name } }
    {
      'summary' => {
        'message_id' => m.id,
        'date' => m.date,
        'from' => mkperson[m.from],
        'to' => m.to.map(&mkperson),
        'cc' => m.cc.map(&mkperson),
        'bcc' => m.bcc.map(&mkperson),
        'subject' => m.subj,
        'refs' => m.refs,
        'replytos' => m.replytos,
        'labels' => m.labels.map(&:to_s),
      },
      'raw' => raw ? m.raw_message : nil,
    }
  end

  def query query, offset, limit, raw
    c = 0
    @index.each_message query do |m|
      next if c < offset
      break if c >= offset + limit if limit
      yield result_from_message(m, raw)
      c += 1
    end
    nil
  end

  def count query
    @index.num_results_for query
  end

  def label query, remove_labels, add_labels
    @index.each_message query do |m|
      remove_labels.each { |l| m.remove_label l }
      add_labels.each { |l| m.add_label l }
      @index.update_message_state m
    end
    nil
  end

  def add raw, labels
    SentManager.source.store_message Time.now, "test@example.com" do |io|
      io.write raw
    end
    PollManager.poll_from SentManager.source do |sym,m,old_m|
      next unless sym == :add
      m.labels = labels
    end
    nil
  end

  def thread msg_id, raw
    msg = @index.build_message msg_id
    @index.each_message_in_thread_for msg do |id, builder|
      m = builder.call
      yield result_from_message(m, raw)
    end
  end
end

end
