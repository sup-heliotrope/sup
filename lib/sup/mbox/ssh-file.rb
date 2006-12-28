require 'net/ssh'

module Redwood
module MBox

class SSHFileError < StandardError; end

## this is a file-like interface to a file that actually lives on the
## other end of an ssh connection. it works by using wc, head and tail
## to simulate (buffered) random access.

## it doesn't work very well, because while on a fast connection ssh
## can have a nice bandwidth, the latency is pretty terrible: about 1
## second (!) per request. and since reading mbox files involves
## jumping around a lot all over the file, it is tragically slow to do
## anything with this. i've tried to compensate by caching massive
## amounts of data, but that doesn't really help.
##
## so, your best bet for remote file access remains IMAP.  i'm going
## to include this in the codebase for the time begin, because maybe
## someone very motivated can put some energy into a better approach
## (probably one that doesn't involve the synchronous shell.)

## there are two kinds of file access that are typical in sup: the
## first is an import, which starts at some point in the file and
## reads until the end. the other is during loading time, which does
## arbitrary reads into the file, but typically reads *backwards* in
## the file (because messages are loaded and displayed most recent
## first, and typically later message are later in the mbox file).  so
## we have to be careful that whatever caching we do supports both.

# debugging
# $f = File.open("asdf.txt", "w")
def debuggg s
  # $f.puts s
  # $f.flush
end
module_function :debuggg

class Buffer
  def initialize
    clear!
  end

  def clear!
    MBox::debuggg ">>> CLEARING <<<"
    @start = nil
    @buf = ""
  end

  def empty?; @start.nil?; end
  def start; @start; end
  def endd; @start + @buf.length; end

  def add data, offset=endd
    MBox::debuggg "+ adding #{data.length} bytes; size will be #{size + data.length}; limit #{SSHFile::MAX_BUF_SIZE}"

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

class SSHFile
  MAX_BUF_SIZE = 1024 * 1024 * 3
  MAX_TRANSFER_SIZE = 1024 * 64 # bytes
  REASONABLE_TRANSFER_SIZE = 1024 * 4 # bytes
  SIZE_CHECK_INTERVAL = 60 * 1 # seconds

  def initialize host, fn, ssh_opts={}
    @buf = Buffer.new
    @host = host
    @fn = fn
    @ssh_opts = ssh_opts
    @file_size = nil
  end

  def connect
    return if @session
    # MBox::debuggg "starting session..."
    @session = Net::SSH.start @host, @ssh_opts
    # MBox::debuggg "starting shell..."
    # @shell = @session.shell.sync
    @input, @output, @error = @session.process.popen3("/bin/sh")

    # MBox::debuggg "ready for heck!"
    raise Errno::ENOENT, @fn unless do_remote("if [ -e #@fn ]; then echo y; else echo n; fi").chomp == "y"
  end

  def eof?; @offset >= size; end
  def eof; eof?; end # lame but IO does this and rmail depends on it

  def seek loc
    # MBox::debuggg "seeking to #{loc} from #@offset"
    @offset = loc
  end
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

    line = @buf[@offset .. (@buf.index("\n", @offset) || -1)]
    @offset += line.length
    # MBox::debuggg "gets is of length #{line.length}, offset now #@offset"
    line
  end

  def read n
    return nil if eof?

    make_buf_include @offset, n
    @buf[@offset ... (@offset += n)]
  end

private

  def do_remote cmd, expected_size=0
    retries = 0
    connect
    MBox::debuggg "sending command: #{cmd.inspect}"
    begin
      @input.puts cmd
      result = ""
      begin
        result += @output.read 
      end while result.length < expected_size
      # result = @shell.send_command cmd
      
      #raise SSHFileError, "Unable to perform remote command #{cmd.inspect}: #{result.stderr[0 .. 100]}" unless result.status == 0
    rescue Net::SSH::Exception
      retry if (retries += 1) < 3
      raise
    end
    result
    #result.stdout
  end

  def get_bytes offset, size
    MBox::debuggg "get_bytes(#{offset}, #{size})"
    MBox::debuggg "! request for [#{offset}, #{offset + size}); buf is #@buf"
    raise "wtf: offset #{offset} size #{size}" if size == 0 || offset < 0
    do_remote "tail -c +#{offset + 1} #@fn | head -c #{size}", size
  end

  def expand_buf_forward n=REASONABLE_TRANSFER_SIZE
    @buf.add get_bytes(@buf.endd, n)
    # trim if necessary
  end

  ## try our best to transfer somewhere between
  ## REASONABLE_TRANSFER_SIZE and MAX_TRANSFER_SIZE bytes
  def make_buf_include offset, size=0
    good_size = [size, REASONABLE_TRANSFER_SIZE].max
    remainder = good_size - size

    trans_start, trans_size = 
      if @buf.empty?
        [[offset - (remainder / 2), 0].max, good_size]
      elsif offset < @buf.start
        if @buf.start - offset <= good_size
          start = [@buf.start - good_size, 0].max
          [start, @buf.start - start]
        elsif @buf.start - offset < MAX_TRANSFER_SIZE
          [offset, @buf.start - offset]
        else
          MBox::debuggg "clearing buffer because buf.start #{@buf.start} - offset #{offset} >= #{MAX_TRANSFER_SIZE}"
          @buf.clear!
          [[offset - (remainder / 2), 0].max, good_size]
        end
      else
        return if [offset + size, self.size].min <= @buf.endd # whoohoo!
        if offset - @buf.endd <= good_size
          [@buf.endd, good_size]
        elsif offset - @buf.endd < MAX_TRANSFER_SIZE
          [@buf.endd, offset - @buf.endd]
        else
          MBox::debuggg "clearing buffer because offset #{offset} - buf.end #{@buf.endd} >= #{MAX_TRANSFER_SIZE}"
          @buf.clear!
          [[offset - (remainder / 2), 0].max, good_size]
        end
      end          

    MBox::debuggg "make_buf_include(#{offset}, #{size})"
    @buf.clear! if @buf.size > MAX_BUF_SIZE
    @buf.add get_bytes(trans_start, trans_size), trans_start
  end
end

end
end
