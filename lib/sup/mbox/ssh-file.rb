require 'net/ssh'

module Redwood
module MBox

class SSHFileError < StandardError; end

## this is a file-like interface to a file that actually lives on the
## other end of an ssh connection. it works by using wc, head and tail
## to simulate (buffered) random access. on a fast connection, this
## can have a good bandwidth, but the latency is pretty terrible:
## about 1 second (!) per request.  luckily, we're either just reading
## straight through the mbox (an import) or we're reading a few
## messages at a time (viewing messages) so the latency is not a problem.

## all of the methods here catch SSHFileErrors, SocketErrors, and
## Net::SSH::Exceptions and reraise them as SourceErrors. due to this
## and to the logging, this class is somewhat tied to Sup, but it
## wouldn't be too difficult to remove those bits and make it more
## general-purpose.

## debugging TODO: remove me
def debug s
  Redwood::log s
end
module_function :debug

## a simple buffer of contiguous data
class Buffer
  def initialize
    clear!
  end

  def clear!
    @start = nil
    @buf = ""
  end

  def empty?; @start.nil?; end
  def start; @start; end
  def endd; @start + @buf.length; end

  def add data, offset=endd
    #MBox::debug "+ adding #{data.length} bytes; size will be #{size + data.length}; limit #{SSHFile::MAX_BUF_SIZE}"

    if start.nil?
      @buf = data
      @start = offset
      return
    end

    raise "non-continguous data added to buffer (data #{offset}:#{offset + data.length}, buf range #{start}:#{endd})" if offset + data.length < start || offset > endd

    if offset < start
      @buf = data[0 ... (start - offset)] + @buf
      @start = offset
    else
      return if offset + data.length < endd
      @buf += data[(endd - offset) .. -1]
    end
  end

  def [](o)
    raise "only ranges supported due to programmer's laziness" unless o.is_a? Range
    @buf[Range.new(o.first - @start, o.last - @start, o.exclude_end?)]
  end

  def index what, start=0
    x = @buf.index(what, start - @start)
    x.nil? ? nil : x + @start
  end
  def rindex what, start=0
    x = @buf.rindex(what, start - @start)
    x.nil? ? nil : x + @start
  end

  def size; empty? ? 0 : @buf.size; end
  def to_s; empty? ? "<empty>" : "[#{start}, #{endd})"; end # for debugging
end

## the file-like interface to a remote file
class SSHFile
  MAX_BUF_SIZE = 1024 * 1024 # bytes
  MAX_TRANSFER_SIZE = 1024 * 64
  REASONABLE_TRANSFER_SIZE = 1024 * 32
  SIZE_CHECK_INTERVAL = 60 * 1 # seconds

  def initialize host, fn, ssh_opts={}
    @buf = Buffer.new
    @host = host
    @fn = fn
    @ssh_opts = ssh_opts
    @file_size = nil
    @offset = 0
  end

  def connect
    return if @session

    Redwood::log "starting SSH session to #@host for #@fn..."
    sid = BufferManager.say "Connecting to SSH host #{@host}..." if BufferManager.instantiated?

    begin
      @session = Net::SSH.start @host, @ssh_opts
      MBox::debug "starting SSH shell..."
      BufferManager.say "Starting SSH shell...", sid if BufferManager.instantiated?
      @shell = @session.shell.sync
      MBox::debug "checking for file existence..."
      raise Errno::ENOENT, @fn unless @shell.test("-e #@fn").status == 0
      MBox::debug "SSH is ready"
    ensure 
      BufferManager.clear sid if BufferManager.instantiated?
    end
  end

  def eof?; raise "offset #@offset size #{size}" unless @offset && size; @offset >= size; end
  def eof; eof?; end # lame but IO does this and rmail depends on it
  def seek loc; raise "nil" unless loc; @offset = loc; end
  def tell; @offset; end
  def total; size; end

  def size
    if @file_size.nil? || (Time.now - @last_size_check) > SIZE_CHECK_INTERVAL
      @last_size_check = Time.now
      @file_size = do_remote("wc -c #@fn").split.first.to_i
    end
    @file_size
  end

  def gets
    return nil if eof?

    make_buf_include @offset
    expand_buf_forward while @buf.index("\n", @offset).nil? && @buf.endd < size

    with(@buf[@offset .. (@buf.index("\n", @offset) || -1)]) { |line| @offset += line.length }
  end

  def read n
    return nil if eof?
    make_buf_include @offset, n
    @buf[@offset ... (@offset += n)]
  end

private

  def do_remote cmd, expected_size=0
    begin
      retries = 0
      connect
      MBox::debug "sending command: #{cmd.inspect}"
      begin
        result = @shell.send_command cmd
        raise SSHFileError, "Failure during remote command #{cmd.inspect}: #{result.stderr[0 .. 100]}" unless result.status == 0

      rescue Net::SSH::Exception # these happen occasionally for no apparent reason. gotta love that nondeterminism!
        retry if (retries += 1) < 3
        raise
      end
      result.stdout
    rescue Net::SSH::Exception, SocketError, Errno::ENOENT => e
      @session = nil
      Redwood::log "error connecting to SSH server: #{e.message}"
      raise SourceError, "error connecting to SSH server: #{e.message}"
    end
  end

  def get_bytes offset, size
    #MBox::debug "! request for [#{offset}, #{offset + size}); buf is #@buf"
    raise "wtf: offset #{offset} size #{size}" if size == 0 || offset < 0
    do_remote "tail -c +#{offset + 1} #@fn | head -c #{size}", size
  end

  def expand_buf_forward n=REASONABLE_TRANSFER_SIZE
    @buf.add get_bytes(@buf.endd, n)
  end

  ## try our best to transfer somewhere between
  ## REASONABLE_TRANSFER_SIZE and MAX_TRANSFER_SIZE bytes
  def make_buf_include offset, size=0
    good_size = [size, REASONABLE_TRANSFER_SIZE].max

    trans_start, trans_size = 
      if @buf.empty?
        [offset, good_size]
      elsif offset < @buf.start
        if @buf.start - offset <= good_size
          start = [@buf.start - good_size, 0].max
          [start, @buf.start - start]
        elsif @buf.start - offset < MAX_TRANSFER_SIZE
          [offset, @buf.start - offset]
        else
          MBox::debug "clearing SSH buffer because buf.start #{@buf.start} - offset #{offset} >= #{MAX_TRANSFER_SIZE}"
          @buf.clear!
          [offset, good_size]
        end
      else
        return if [offset + size, self.size].min <= @buf.endd # whoohoo!
        if offset - @buf.endd <= good_size
          [@buf.endd, good_size]
        elsif offset - @buf.endd < MAX_TRANSFER_SIZE
          [@buf.endd, offset - @buf.endd]
        else
          MBox::debug "clearing SSH buffer because offset #{offset} - buf.end #{@buf.endd} >= #{MAX_TRANSFER_SIZE}"
          @buf.clear!
          [offset, good_size]
        end
      end          

    @buf.clear! if @buf.size > MAX_BUF_SIZE
    @buf.add get_bytes(trans_start, trans_size), trans_start
  end
end

end
end
