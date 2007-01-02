require 'net/ssh'

module Redwood
module MBox

## this is slightly complicated because SSHFile (and thus @f or
## @loader) can throw a variety of exceptions, and we need to catch
## those, reraise them as SourceErrors, and set ourselves as broken.

class SSHLoader < Source
  attr_reader_cloned :labels
  attr_accessor :username, :password

  def initialize uri, username=nil, password=nil, start_offset=nil, usual=true, archived=false, id=nil
    raise ArgumentError, "not an mbox+ssh uri: #{uri.inspect}" unless uri =~ %r!^mbox\+ssh://!

    super uri, start_offset, usual, archived, id

    @parsed_uri = URI(uri)
    @username = username
    @password = password
    @uri = uri
    @cur_offset = start_offset

    opts = {}
    opts[:username] = @username if @username
    opts[:password] = @password if @password
    
    @f = SSHFile.new host, filename, opts
    @loader = Loader.new @f, start_offset, usual, archived, id
    
    ## heuristic: use the filename as a label, unless the file
    ## has a path that probably represents an inbox.
    @labels = [:unread]
    @labels << :inbox unless archived?
    @labels << File.basename(filename).intern unless File.dirname(filename) =~ /\b(var|usr|spool)\b/
  end

  def host; @parsed_uri.host; end
  def filename; @parsed_uri.path[1..-1] end

  def next
    return if broken?
    begin
      offset, labels = @loader.next
      self.cur_offset = @loader.cur_offset # superclass keeps @cur_offset which is used by yaml
      [offset, (labels + @labels).uniq] # add our labels
    rescue Net::SSH::Exception, SocketError, SSHFileError, Errno::ENOENT => e
      recover_from e
    end
  end

  def end_offset
    begin
      @f.size
    rescue Net::SSH::Exception, SocketError, SSHFileError, Errno::ENOENT => e
      recover_from e
    end
  end

  def cur_offset= o; @cur_offset = @loader.cur_offset = o; @dirty = true; end
  def id; @loader.id; end
  def id= o; @id = @loader.id = o; end
  # def cur_offset; @loader.cur_offset; end # think we'll be ok without this
  def to_s; @parsed_uri.to_s; end

  def recover_from e
    m = "error communicating with SSH server #{host} (#{e.class.name}): #{e.message}"
    Redwood::log m
    self.broken_msg = @loader.broken_msg = m
    raise SourceError, m
  end

  [:start_offset, :load_header, :load_message, :raw_header, :raw_full_message].each do |meth|
    define_method meth do |*a|
      begin
        @loader.send meth, *a
      rescue Net::SSH::Exception, SocketError, SSHFileError, Errno::ENOENT => e
        recover_from e
      end
    end
  end
end

Redwood::register_yaml(SSHLoader, %w(uri username password cur_offset usual archived id))

end
end
