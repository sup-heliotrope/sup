require 'uri'
require 'net/imap'
require 'stringio'

module Redwood

class IMAP < Source
  attr_reader :labels
  
  def initialize uri, username, password, last_uid=nil, usual=true, archived=false, id=nil
    raise ArgumentError, "username and password must be specified" unless username && password

    super uri, last_uid, usual, archived, id

    @parsed_uri = URI(uri)
    @username = username
    @password = password
    @imap = nil
    @labels = [:unread]
    @labels << mailbox.intern unless mailbox =~ /inbox/i || mailbox.empty?
    @labels << :inbox unless archived?

    connect
  end

  def connect
    return false if broken?
    return true if @imap
    Redwood::log "connecting to #{@parsed_uri.host} port #{ssl? ? 993 : 143}, ssl=#{ssl?} ..."

    ## ok, this is FUCKING ANNOYING.
    ##
    ## what imap.rb likes to do is, if an exception occurs, catch it
    ## and re-raise it on the calling thread. seems reasonable. but
    ## what that REALLY means is that the only way to reasonably
    ## initialize imap is in its own thread, because otherwise, you
    ## will never be able to catch the exception it raises on the
    ## calling thread, and the backtrace will not make any sense at
    ## all, and you will waste HOURS of your life on this fucking
    ## problem.
    ##
    ## FUCK!!!!!!!!!
    ::Thread.new do
      begin
        #raise Net::IMAP::ByeResponseError, "simulated imap failure"
        @imap = Net::IMAP.new @parsed_uri.host, ssl? ? 993 : 143, ssl?
        @imap.authenticate 'LOGIN', @username, @password
        @imap.examine mailbox
        Redwood::log "successfully connected to #{@parsed_uri}, mailbox #{mailbox}"
      rescue Exception => e
        self.broken_msg = e.message.chomp # fucking chomp! fuck!!!
        @imap = nil
        Redwood::log "error connecting to IMAP server: #{self.broken_msg}"
      end
    end.join

    !!@imap
  end
  private :connect

  def mailbox; @parsed_uri.path[1..-1] end ##XXXX TODO handle nil
  def ssl?; @parsed_uri.scheme == 'imaps' end

  def load_header uid=nil
    MBox::read_header StringIO.new(raw_header(uid))
  end

  def load_message uid
    RMail::Parser.read raw_full_message(uid)
  end

  ## load the full header text
  def raw_header uid
    connect or return broken_msg
    begin
      connect or return broken_msg
    rescue Exception => e
      raise "wtf: #{e.inspect}"
    end
    @imap.uid_fetch(uid, 'RFC822.HEADER')[0].attr['RFC822.HEADER'].gsub(/\r\n/, "\n")
  end

  def raw_full_message uid
    connect or return broken_msg
    @imap.uid_fetch(uid, 'RFC822')[0].attr['RFC822'].gsub(/\r\n/, "\n")
  end
  
  def each
    connect or return broken_msg
    uids = @imap.uid_search ['UID', "#{cur_offset}:#{end_offset}"]
    uids.each do |uid|
      @last_uid = uid
      @dirty = true
      yield uid, labels
    end
  end

  def start_offset; 1; end
  def end_offset
    connect or return start_offset
    @imap.uid_search(['ALL']).last
  end
end

Redwood::register_yaml(IMAP, %w(uri username password offset usual archived id))

end
