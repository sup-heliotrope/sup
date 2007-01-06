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
  SCAN_INTERVAL = 60 # seconds

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
    @last_scan = nil
    @labels = [:unread]
    @labels << :inbox unless archived?
    @labels << mailbox.intern unless mailbox =~ /inbox/i
    @mutex = Mutex.new
  end

  def host; @parsed_uri.host; end
  def port; @parsed_uri.port || (ssl? ? 993 : 143); end
  def mailbox
    x = @parsed_uri.path[1..-1]
    x.nil? || x.empty? ? 'INBOX' : x
  end
  def ssl?; @parsed_uri.scheme == 'imaps' end

  def load_header id
    MBox::read_header StringIO.new(raw_header(id))
  end

  def load_message id
    RMail::Parser.read raw_full_message(id)
  end

  def raw_header id
    @mutex.synchronize do
      connect
      header, flags = get_imap_fields id, 'RFC822.HEADER', 'FLAGS'
      header = "Status: RO\n" + header if flags.include? :Seen # fake an mbox-style read header
      header.gsub(/\r\n/, "\n")
    end
  end

  def raw_full_message id
    @mutex.synchronize do
      connect
      get_imap_fields(id, 'RFC822').first.gsub(/\r\n/, "\n")
    end
  end

  def connect
    return false if broken?
    return true if @imap

    say "Connecting to IMAP server #{host}:#{port}..."

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

    exception = nil
    Redwood::reporting_thread do
      begin
        #raise Net::IMAP::ByeResponseError, "simulated imap failure"
        @imap = Net::IMAP.new host, port, ssl?
        say "Logging in..."
        begin
          @imap.authenticate 'CRAM-MD5', @username, @password
        rescue Net::IMAP::BadResponseError, Net::IMAP::NoResponseError => e
          say "CRAM-MD5 authentication failed: #{e.class}"
          begin
            @imap.authenticate 'LOGIN', @username, @password
          rescue Net::IMAP::BadResponseError, Net::IMAP::NoResponseError => e
            say "LOGIN authentication failed: #{e.class}"
            @imap.login @username, @password
          end
        end
        scan_mailbox
        say "Successfully connected to #{@parsed_uri}."
      rescue SocketError, Net::IMAP::Error, SourceError => e
        exception = e
      ensure
        shutup
      end
    end.join

    die_from exception, :while => "connecting" if exception
  end

  def each
    @mutex.synchronize { connect or raise SourceError, broken_msg }

    start = @ids.index(cur_offset || start_offset) or die_from "Unknown message id #{cur_offset || start_offset}.", :suggest_rebuild => true # couldn't find the most recent email

    start.upto(@ids.length - 1) do |i|         
      id = @ids[i]
      self.cur_offset = id
      yield id, labels
    end
  end

  def start_offset
    @mutex.synchronize { connect }
    @ids.first
  end

  def end_offset
    @mutex.synchronize do
      begin
        connect
        scan_mailbox
      rescue SocketError, Net::IMAP::Error => e
        die_from e, :while => "scanning mailbox"
      end
    end
    @ids.last
  end

  def pct_done; 100.0 * (@ids.index(cur_offset) || 0).to_f / (@ids.length - 1).to_f; end

private

  def say s
    @say_id = BufferManager.say s, @say_id if BufferManager.instantiated?
    Redwood::log s
  end

  def shutup
    BufferManager.clear @say_id if BufferManager.instantiated?
    @say_id = nil
  end

  def scan_mailbox
    return if @last_scan && (Time.now - @last_scan) < SCAN_INTERVAL

    @imap.examine mailbox
    last_id = @imap.responses["EXISTS"].last
    @last_scan = Time.now
    return if last_id == @ids.length
    Redwood::log "fetching IMAP headers #{(@ids.length + 1) .. last_id}"
    values = @imap.fetch((@ids.length + 1) .. last_id, ['RFC822.SIZE', 'INTERNALDATE'])
    values.each do |v|
      id = make_id v
      @ids << id
      @imap_ids[id] = v.seqno
    end
  end

  def die_from e, opts={}
    @imap = nil

    message =
      case e
      when Exception
        "Error while #{opts[:while]}: #{e.message.chomp} (#{e.class.name})."
      when String
        e
      end

    message += " It is likely that messages have been deleted from this IMAP mailbox. Please run sup-import --rebuild #{to_s} to correct this problem." if opts[:suggest_rebuild]

    self.broken_msg = message
    Redwood::log message
    BufferManager.flash "Error communicating with IMAP server. See log for details." if BufferManager.instantiated?
    raise SourceError, message
  end
  
  ## build a fake unique id
  def make_id imap_stuff
    # use 7 digits for the size. why 7? seems nice.
    msize, mdate = imap_stuff.attr['RFC822.SIZE'] % 10000000, Time.parse(imap_stuff.attr["INTERNALDATE"])
    sprintf("%d%07d", mdate.to_i, msize).to_i
  end

  def get_imap_fields id, *fields
    retries = 0
    f = nil
    imap_id = @imap_ids[id] or die_from "Unknown message id #{id}.", :suggest_rebuild => true
    begin
      f = @imap.fetch imap_id, (fields + ['RFC822.SIZE', 'INTERNALDATE']).uniq
      got_id = make_id f[0]
      die_from "IMAP message mismatch: requested #{id}, got #{got_id}.", :suggest_rebuild => true unless id == got_id
    rescue SocketError, Net::IMAP::Error => e
      die_from e, :while => "communicating with IMAP server"
    rescue Errno::EPIPE
      if (retries += 1) <= 3
        @imap = nil
        connect
        retry
      end
    end
    die_from "Null IMAP field '#{field}' for message with id #{id} imap id #{imap_id}." if f.nil?

    fields.map { |field| f[0].attr[field] }
  end
end

Redwood::register_yaml(IMAP, %w(uri username password cur_offset usual archived id))

end
