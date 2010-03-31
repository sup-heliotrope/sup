module Redwood

## Hacky implementation of the sup-server API using existing Sup code
class Connection
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
    Index.each_message query do |m|
      next if c < offset
      break if c >= offset + limit if limit
      yield result_from_message(m, raw)
      c += 1
    end
    nil
  end

  def count query
    Index.num_results_for query
  end

  def label query, remove_labels, add_labels
    Index.each_message query do |m|
      remove_labels.each { |l| m.remove_label l }
      add_labels.each { |l| m.add_label l }
      Index.update_message_state m
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
end

end
