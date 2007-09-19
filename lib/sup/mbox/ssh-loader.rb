require 'net/ssh'

module Redwood
module MBox

class SSHLoader < Source
  attr_accessor :username, :password

  yaml_properties :uri, :username, :password, :cur_offset, :usual, 
                  :archived, :id, :labels

  def initialize uri, username=nil, password=nil, start_offset=nil, usual=true, archived=false, id=nil, labels=[]
    raise ArgumentError, "not an mbox+ssh uri: #{uri.inspect}" unless uri =~ %r!^mbox\+ssh://!

    super uri, start_offset, usual, archived, id

    @parsed_uri = URI(uri)
    @username = username
    @password = password
    @uri = uri
    @cur_offset = start_offset
    @labels = (labels || []).freeze

    opts = {}
    opts[:username] = @username if @username
    opts[:password] = @password if @password
    
    @f = SSHFile.new host, filename, opts
    @loader = Loader.new @f, start_offset, usual, archived, id
    
    ## heuristic: use the filename as a label, unless the file
    ## has a path that probably represents an inbox.
  end

  def self.suggest_labels_for path; Loader.suggest_labels_for(path) end

  def connect; safely { @f.connect }; end
  def host; @parsed_uri.host; end
  def filename; @parsed_uri.path[1..-1] end

  def next
    safely do
      offset, labels = @loader.next
      self.cur_offset = @loader.cur_offset # superclass keeps @cur_offset which is used by yaml
      [offset, (labels + @labels).uniq] # add our labels
    end
  end

  def end_offset
    safely { @f.size }
  end

  def cur_offset= o; @cur_offset = @loader.cur_offset = o; @dirty = true; end
  def id; @loader.id; end
  def id= o; @id = @loader.id = o; end
  # def cur_offset; @loader.cur_offset; end # think we'll be ok without this
  def to_s; @parsed_uri.to_s; end

  def safely
    begin
      yield
    rescue Net::SSH::Exception, SocketError, SSHFileError, SystemCallError, IOError => e
      m = "error communicating with SSH server #{host} (#{e.class.name}): #{e.message}"
      raise FatalSourceError, m
    end
  end

  [:start_offset, :load_header, :load_message, :raw_header, :raw_message].each do |meth|
    define_method(meth) { |*a| safely { @loader.send meth, *a } }
  end
end

end
end
