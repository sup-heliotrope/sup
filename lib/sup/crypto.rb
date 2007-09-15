module Redwood

class CryptoManager
  include Singleton

  def initialize
    @mutex = Mutex.new
    self.class.i_am_the_instance self

    @cmd = `which gpg`.chomp
    @cmd = `which pgp`.chomp unless @cmd =~ /\S/
    @cmd = nil unless @cmd =~ /\S/
  end

  def verify payload, signature # both RubyMail::Message objects
    return unknown unless @cmd

    payload_fn = File.open("payload", "w") # Tempfile.new "redwood.payload"
    signature_fn = File.open("signature", "w") #Tempfile.new "redwood.signature"

    payload_fn.write payload.to_s.gsub(/(^|[^\r])\n/, "\\1\r\n").gsub(/^MIME-Version: .*\r\n/, "")
    payload_fn.close

    signature_fn.write signature.decode
    signature_fn.close

    cmd = "#{@cmd} --quiet --batch --no-verbose --verify --logger-fd 1 #{signature_fn.path} #{payload_fn.path} 2> /dev/null"

    #Redwood::log "gpg: running: #{cmd}"
    gpg_output = `#{cmd}`
    #Redwood::log "got output: #{gpg_output.inspect}"
    lines = gpg_output.split(/\n/)

    if gpg_output =~ /^gpg: (.* signature from .*$)/
      $? == 0 ? [:valid, $1, lines] : [:invalid, $1, lines]
    else
      unknown lines
    end
  end

private

  def unknown lines=[]
    [:unknown, "Unable to determine validity of cryptographic signature", lines]
  end
end
end
