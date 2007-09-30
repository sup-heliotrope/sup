module Redwood

class CryptoManager
  include Singleton

  def initialize
    @mutex = Mutex.new
    self.class.i_am_the_instance self

    bin = `which gpg`.chomp
    bin = `which pgp`.chomp unless bin =~ /\S/

    @cmd =
      case bin
      when /\S/
        "#{bin} --quiet --batch --no-verbose --logger-fd 1 --use-agent"
      else
        nil
      end
  end

  # returns a cryptosignature
  def verify payload, signature # both RubyMail::Message objects
    return unknown_status(cant_find_binary) unless @cmd

    payload_fn = Tempfile.new "redwood.payload"
    payload_fn.write payload.to_s.gsub(/(^|[^\r])\n/, "\\1\r\n").gsub(/^MIME-Version: .*\r\n/, "")
    payload_fn.close

    signature_fn = Tempfile.new "redwood.signature"
    signature_fn.write signature.decode
    signature_fn.close

    cmd = "#{@cmd} --verify #{signature_fn.path} #{payload_fn.path} 2> /dev/null"

    #Redwood::log "gpg: running: #{cmd}"
    gpg_output = `#{cmd}`
    #Redwood::log "got output: #{gpg_output.inspect}"
    output_lines = gpg_output.split(/\n/)

    if gpg_output =~ /^gpg: (.* signature from .*$)/
      if $? == 0
        Chunk::CryptoNotice.new :valid, $1, output_lines
      else
        Chunk::CryptoNotice.new :invalid, $1, output_lines
      end
    else
      unknown_status output_lines
    end
  end

  # returns decrypted_message, status, desc, lines
  def decrypt payload # RubyMail::Message objects
    return unknown_status(cant_find_binary) unless @cmd

#    cmd = "#{@cmd} --decrypt 2> /dev/null"

#    Redwood::log "gpg: running: #{cmd}"

#    gpg_output =
#      IO.popen(cmd, "a+") do |f|
#        f.puts payload.to_s
#        f.gets
#      end

    payload_fn = Tempfile.new "redwood.payload"
    payload_fn.write payload.to_s
    payload_fn.close

    cmd = "#{@cmd} --decrypt #{payload_fn.path} 2> /dev/null"
    Redwood::log "gpg: running: #{cmd}"
    gpg_output = `#{cmd}`
    Redwood::log "got output: #{gpg_output.inspect}"

    if $? == 0 # successful decryption
      decrypted_payload, sig_lines =
        if gpg_output =~ /\A(.*?)((^gpg: .*$)+)\Z/m
          [$1, $2]
        else
          [gpg_output, nil]
        end
      
      sig = 
        if sig_lines # encrypted & signed
          if sig_lines =~ /^gpg: (Good signature from .*$)/
            Chunk::CryptoNotice.new :valid, $1, sig_lines.split("\n")
          else
            Chunk::CryptoNotice.new :invalid, $1, sig_lines.split("\n")
          end
        end

      notice = Chunk::CryptoNotice.new :valid, "This message has been decrypted for display"
      [RMail::Parser.read(decrypted_payload), sig, notice]
    else
      notice = Chunk::CryptoNotice.new :invalid, "This message could not be decrypted", gpg_output.split("\n")
      [nil, nil, notice]
    end
  end

private

  def unknown_status lines=[]
    Chunk::CryptoNotice.new :unknown, "Unable to determine validity of cryptographic signature", lines
  end
  
  def cant_find_binary
    ["Can't find gpg or pgp binary in path"]
  end
end
end
