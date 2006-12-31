require 'net/ssh'

module Redwood
module MBox

class SSHLoader < Source
  attr_reader_cloned :labels

  def initialize uri, username=nil, password=nil, start_offset=nil, usual=true, archived=false, id=nil
    raise ArgumentError, "not an mbox+ssh uri: #{uri.inspect}" unless uri =~ %r!^mbox\+ssh://!

    super uri, start_offset, usual, archived, id

    @parsed_uri = URI(uri)
    @username = username
    @password = password
    @uri = uri

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
  def filename; @parsed_uri.path[1..-1] end ##XXXX TODO handle nil

  def next; with(@loader.next) { @cur_offset = @loader.cur_offset }; end # only necessary because YAML is a PITA
  def end_offset; @f.size; end
  def cur_offset= o; @cur_offset = @loader.cur_offset = o; @dirty = true; end
  def id; @loader.id; end
  def id= o; @id = @loader.id = o; end
  def cur_offset; @loader.cur_offset; end
  def to_s; @parsed_uri.to_s; end

  defer_all_other_method_calls_to :loader
end

Redwood::register_yaml(SSHLoader, %w(uri username password cur_offset usual archived id))

end
end
