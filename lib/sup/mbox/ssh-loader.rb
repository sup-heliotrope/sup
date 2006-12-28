require 'net/ssh'

module Redwood
module MBox

class SSHLoader < Loader
  def initialize uri, username=nil, password=nil, start_offset=nil, usual=true, archived=false, id=nil
    raise ArgumentError, "not an mbox+ssh uri" unless uri =~ %r!^mbox\+ssh://!

    @parsed_uri = URI(uri)
    @username = username
    @password = password
    @f = nil

    opts = {}
    opts[:username] = @username if @username
    opts[:password] = @password if @password
    
    @f = SSHFile.new host, filename, opts
    super @f, start_offset, usual, archived, id
    @uri = uri
    ## heuristic: use the filename as a label, unless the file
    ## has a path that probably represents an inbox.
    @labels << File.basename(filename).intern unless File.dirname(filename) =~ /\b(var|usr|spool)\b/
  end

  def host; @parsed_uri.host; end
  def filename; @parsed_uri.path[1..-1] end ##XXXX TODO handle nil

  def end_offset; @f.size; end
  def to_s; @parsed_uri.to_s; end
end

Redwood::register_yaml(SSHLoader, %w(uri username password cur_offset usual archived id))

end
end
