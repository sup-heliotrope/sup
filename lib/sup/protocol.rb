require 'eventmachine'
require 'socket'
require 'stringio'
require 'yajl'

class EM::P::Redwood < EM::Connection
  VERSION = 1
  ENCODINGS = %w(marshal json)

  def initialize *args
    @state = :negotiating
    @version_buf = ""
    super
  end

  def receive_data data
    if @state == :negotiating
      @version_buf << data
      if i = @version_buf.index("\n")
        l = @version_buf.slice!(0..i)
        receive_version *parse_version(l.strip)
        x = @version_buf
        @version_buf = nil
        @state = :established
        connection_established
        receive_data x
      end
    else
      @filter.decode(data).each { |msg| receive_message *msg }
    end
  end

  def connection_established
  end

  def send_version encodings, extensions
    fail if encodings.empty?
    send_data "Redwood #{VERSION} #{encodings * ','} #{extensions.empty? ? :none : (extensions * ',')}\n"
  end

  def send_message type, tag, params={}
    fail "attempted to send message during negotiation" unless @state == :established
    send_data @filter.encode([type,tag,params])
  end

  def receive_version l
    fail "unimplemented"
  end

  def receive_message type, params
    fail "unimplemented"
  end

private

  def parse_version l
    l =~ /^Redwood\s+(\d+)\s+([\w,]+)\s+([\w,]+)$/ or fail "unexpected banner #{l.inspect}"
    version, encodings, extensions = $1.to_i, $2, $3
    encodings = encodings.split ','
    extensions = extensions.split ','
    extensions = [] if extensions == ['none']
    fail unless version == VERSION
    fail if encodings.empty?
    [encodings, extensions]
  end

  def create_filter encoding
    case encoding
    when 'json' then JSONFilter.new
    when 'marshal' then MarshalFilter.new
    else fail "unknown encoding #{encoding.inspect}"
    end
  end

  class JSONFilter
    def initialize
      @parser = Yajl::Parser.new :check_utf8 => false
    end

    def decode chunk
      parsed = []
      @parser.on_parse_complete = lambda { |o| parsed << o }
      @parser << chunk
      parsed
    end

    def encode *os
      os.inject('') { |s, o| s << Yajl::Encoder.encode(o) }
    end
  end

  class MarshalFilter
    def initialize
      @buf = ''
      @state = :prefix
      @size = 0
    end

    def decode chunk
      received = []
      @buf << chunk

      begin
        if @state == :prefix
          break unless @buf.size >= 4
          prefix = @buf.slice!(0...4)
          @size = prefix.unpack('N')[0]
          @state = :data
        end

        fail unless @state == :data
        break if @buf.size < @size
        received << Marshal.load(@buf.slice!(0...@size))
        @state = :prefix
      end until @buf.empty?

      received
    end

    def encode o
      data = Marshal.dump o
      [data.size].pack('N') + data
    end
  end
end

class EM::P::RedwoodServer < EM::P::Redwood
  def post_init
    send_version ENCODINGS, []
  end

  def receive_version encodings, extensions
    fail unless encodings.size == 1
    fail unless ENCODINGS.member? encodings.first
    @filter = create_filter encodings.first
  end
end

class EM::P::RedwoodClient < EM::P::Redwood
  def receive_version encodings, extensions
    encoding = (ENCODINGS & encodings).first
    fail unless encoding
    @filter = create_filter encoding
    send_version [encoding], []
  end
end
