require 'sup/protocol'

class Redwood::Client < EM::P::RedwoodClient
  def initialize *a
    @next_tag = 1
    @cbs = {}
    super *a
  end

  def mktag &b
    @next_tag.tap do |x|
      @cbs[x] = b
      @next_tag += 1
    end
  end

  def rmtag tag
    @cbs.delete tag
  end

  def query qstr, offset, limit, raw, &b
    tag = mktag do |type,tag,args|
      if type == 'message'
        b.call args
      else
        fail unless type == 'done'
        b.call nil
        rmtag tag
      end
    end
    send_message 'query', tag,
                 'query' => qstr,
                 'offset' => offset,
                 'limit' => limit,
                 'raw' => raw
  end

  def count qstr, &b
    tag = mktag do |type,tag,args|
      b.call args['count']
      rmtag tag
    end
    send_message 'count', tag,
                 'query' => qstr
  end

  def label qstr, add, remove, &b
    tag = mktag do |type,tag,args|
      b.call
      rmtag tag
    end
    send_message 'label', tag,
                 'query' => qstr,
                 'add' => add,
                 'remove' => remove
  end

  def add raw, labels, &b
    tag = mktag do |type,tag,args|
      b.call
      rmtag tag
    end
    send_message 'add', tag,
                 'raw' => raw,
                 'labels' => labels
  end

  def receive_message type, tag, args
    cb = @cbs[tag] or fail "invalid tag #{tag.inspect}"
    cb[type, tag, args]
  end
end
