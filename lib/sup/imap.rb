require 'uri'
require 'net/imap'
require 'stringio'

module Redwood

class IMAP
  attr_reader :uri
  bool_reader :usual, :archived, :read, :dirty
  attr_accessor :id, :labels

  class Error < StandardError; end

  def initialize uri, username, password, last_uid=nil, usual=true, archived=false, id=nil
    raise "username and password must be specified" unless username && password

    @uri_s = uri
    @uri = URI(uri)
    @username = username
    @password = password
    @last_uid = last_uid || 1
    @dirty = false
    @usual = usual
    @archived = archived
    @id = id
    @imap = nil
    @labels = [:unread,
               archived ? nil : :inbox,
               mailbox !~ /inbox/i && !mailbox.empty? ? mailbox.intern : nil,
              ].compact
  end

  def connect
    return if @imap
    Redwood::log "connecting to #{@uri.host} port #{ssl? ? 993 : 143}, ssl=#{ssl?}"
    #raise "simulated imap failure"
    @imap = Net::IMAP.new @uri.host, ssl? ? 993 : 143, ssl?
    @imap.authenticate('LOGIN', @username, @password)
    Redwood::log "success. selecting #{mailbox.inspect}."
    @imap.examine(mailbox)
  end
  private :connect

  def mailbox; @uri.path[1..-1] end ##XXXX TODO handle nil
  def ssl?; @uri.scheme == 'imaps' end
  def reset!; @last_uid = 1; @dirty = true; end
  def == o; o.is_a?(IMAP) && o.uri == uri; end
  def uri; @uri.to_s; end
  def to_s; uri; end
  def is_source_for? s; to_s == s; end

  def load_header uid=nil
    MBox::read_header StringIO.new(raw_header(uid))
  end

  def load_message uid
    RMail::Parser.read raw_full_message(uid)
  end

  ## load the full header text
  def raw_header uid
    connect
    @imap.uid_fetch(uid, 'RFC822.HEADER')[0].attr['RFC822.HEADER'].gsub(/\r\n/, "\n")
  end

  def raw_full_message uid
    connect
    @imap.uid_fetch(uid, 'RFC822')[0].attr['RFC822'].gsub(/\r\n/, "\n")
  end
  
  def each
    connect
    uids = @imap.uid_search ['UID', "#{@last_uid}:#{total}"]
    uids.each do |uid|
      yield uid, labels
      @last_uid = uid
      @dirty = true
    end
  end

  def done?; @last_uid >= total; end

  def total
    connect
    @imap.uid_search(['ALL']).last
  end
end

Redwood::register_yaml(IMAP, %w(uri_s username password last_uid usual archived id))

end
