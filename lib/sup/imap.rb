require 'uri'
require 'net/imap'
require 'stringio'
require 'time'

## fucking imap fucking sucks. what the FUCK kind of committee of
## dunces designed this shit.

## imap talks about 'unique ids' for messages, to be used for
## cross-session identification. great---just what sup needs! except
## it turns out the uids can be invalidated every time the
## 'uidvalidity' value changes on the server, and 'uidvalidity' can
## change without restriction. it can change any time you log in. it
## can change EVERY time you log in. of course the imap spec "strongly
## recommends" that it never change, but there's nothing to stop
## people from just setting it to the current timestamp, and in fact
## that's exactly what the one imap server i have at my disposal
## does. thus the so-called uids are absolutely useless and imap
## provides no cross-session way of uniquely identifying a
## message. but thanks for the "strong recommendation", guys!

## so right now i'm using the 'internal date' and the size of each
## message to uniquely identify it, and i scan over the entire mailbox
## each time i open it to map those things to message ids. that can be
## slow for large mailboxes, and we'll just have to hope that there
## are no collisions. ho ho! a perfectly reasonable solution!

## fuck you, imap committee. you managed to design something as shitty
## as mbox but goddamn THIRTY YEARS LATER.

module Redwood

class IMAP < Source
  attr_reader_cloned :labels
  attr_accessor :username, :password

  def initialize uri, username, password, last_idate=nil, usual=true, archived=false, id=nil
    raise ArgumentError, "username and password must be specified" unless username && password
    raise ArgumentError, "not an imap uri" unless uri =~ %r!imaps?://!

    super uri, last_idate, usual, archived, id

    @parsed_uri = URI(uri)
    @username = username
    @password = password
    @imap = nil
    @imap_ids = {}
    @ids = []
    @labels = [:unread]
    @labels << :inbox unless archived?
    @labels << mailbox.intern unless mailbox =~ /inbox/i || mailbox.nil?
    @mutex = Mutex.new
  end

  def say s
    @say_id = BufferManager.say s, @say_id if BufferManager.instantiated?
    Redwood::log s
  end
  def shutup
    BufferManager.clear @say_id if BufferManager.instantiated?
    @say_id = nil
  end
  private :say, :shutup

  def connect
    return false if broken?
    return true if @imap

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

    say "Connecting to IMAP server #{host}:#{port}..."

    Redwood::reporting_thread do
      begin
        #raise Net::IMAP::ByeResponseError, "simulated imap failure"
        @imap = Net::IMAP.new host, ssl? ? 993 : 143, ssl?
        say "Logging in..."
        @imap.authenticate 'LOGIN', @username, @password
        say "Sizing mailbox..."
        @imap.examine mailbox
        last_id = @imap.responses["EXISTS"][-1]
        
        say "Reading headers (because IMAP sucks)..."
        values = @imap.fetch(1 .. last_id, ['RFC822.SIZE', 'INTERNALDATE'])
        
        say "Successfully connected to #{@parsed_uri}"
        
        values.each do |v|
          id = make_id v
          @ids << id
          @imap_ids[id] = v.seqno
        end
      rescue SocketError, Net::IMAP::Error, SourceError => e
        self.broken_msg = e.message.chomp # fucking chomp! fuck!!!
        @imap = nil
        Redwood::log "error connecting to IMAP server: #{self.broken_msg}"
      ensure
        shutup
      end
    end.join

    !!@imap
  end
  private :connect

  def make_id imap_stuff
    msize, mdate = imap_stuff.attr['RFC822.SIZE'], Time.parse(imap_stuff.attr["INTERNALDATE"])
    sprintf("%d%07d", mdate.to_i, msize).to_i
  end
  private :make_id

  def host; @parsed_uri.host; end
  def port; @parsed_uri.port || (ssl? ? 993 : 143); end
  def mailbox; @parsed_uri.path[1..-1] || 'INBOX'; end
  def ssl?; @parsed_uri.scheme == 'imaps' end

  def load_header id
    MBox::read_header StringIO.new(raw_header(id))
  end

  def load_message id
    RMail::Parser.read raw_full_message(id)
  end

  ## load the full header text
  def raw_header id
    @mutex.synchronize do
      connect or raise SourceError, broken_msg
      get_imap_field(id, 'RFC822.HEADER').gsub(/\r\n/, "\n")
    end
  end

  def raw_full_message id
    @mutex.synchronize do
      connect or raise SourceError, broken_msg
      get_imap_field(id, 'RFC822').gsub(/\r\n/, "\n")
    end
  end

  def get_imap_field id, field
    retries = 0
    f = nil
    imap_id = @imap_ids[id] or raise SourceError, "Unknown message id #{id}. It is likely that messages have been deleted from this IMAP mailbox."
    begin
      f = @imap.fetch imap_id, [field, 'RFC822.SIZE', 'INTERNALDATE']
      got_id = make_id f[0]
      raise SourceError, "IMAP message mismatch: requested #{id}, got #{got_id}. It is likely the IMAP mailbox has been modified." unless got_id == id
    rescue Net::IMAP::Error => e
      raise SourceError, e.message
    rescue Errno::EPIPE
      if (retries += 1) <= 3
        @imap = nil
        connect
        retry
      end
    end
    raise SourceError, "null IMAP field '#{field}' for message with id #{id} imap id #{imap_id}" if f.nil?

    f[0].attr[field]
  end
  private :get_imap_field
  
  def each
    @mutex.synchronize { connect or raise SourceError, broken_msg }

    start = @ids.index(cur_offset || start_offset)
    start.upto(@ids.length - 1) do |i|
      id = @ids[i]
      self.cur_offset = id
      yield id, labels
    end
  end

  def start_offset
    @mutex.synchronize { connect or raise SourceError, broken_msg }
    @ids.first
  end

  def end_offset
    @mutex.synchronize { connect or raise SourceError, broken_msg }
    @ids.last
  end
end

Redwood::register_yaml(IMAP, %w(uri username password cur_offset usual archived id))

end
