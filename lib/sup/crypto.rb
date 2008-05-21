module Redwood

class CryptoManager
  include Singleton

  class Error < StandardError; end

  OUTGOING_MESSAGE_OPERATIONS = OrderedHash.new(
    [:sign, "Sign"],
    [:sign_and_encrypt, "Sign and encrypt"],
    [:encrypt, "Encrypt only"]
  )

  def initialize
    @mutex = Mutex.new
    self.class.i_am_the_instance self

    bin = `which gpg`.chomp

    @cmd =
      case bin
      when /\S/
        Redwood::log "crypto: detected gpg binary in #{bin}"
        "#{bin} --quiet --batch --no-verbose --logger-fd 1 --use-agent"
      else
        Redwood::log "crypto: no gpg binary detected"
        nil
      end
  end

  def have_crypto?; !@cmd.nil? end

  def sign from, to, payload
    payload_fn = Tempfile.new "redwood.payload"
    payload_fn.write format_payload(payload)
    payload_fn.close

    output = run_gpg "--output - --armor --detach-sign --textmode --local-user '#{from}' #{payload_fn.path}"

    raise Error, (output || "gpg command failed: #{cmd}") unless $?.success?

    envelope = RMail::Message.new
    envelope.header["Content-Type"] = 'multipart/signed; protocol=application/pgp-signature; micalg=pgp-sha1'

    envelope.add_part payload
    signature = RMail::Message.make_attachment output, "application/pgp-signature", nil, "signature.asc"
    envelope.add_part signature
    envelope
  end

  def encrypt from, to, payload, sign=false
    payload_fn = Tempfile.new "redwood.payload"
    payload_fn.write format_payload(payload)
    payload_fn.close

    recipient_opts = to.map { |r| "--recipient '<#{r}>'" }.join(" ")
    sign_opts = sign ? "--sign --local-user '#{from}'" : ""
    gpg_output = run_gpg "--output - --armor --encrypt --textmode #{sign_opts} #{recipient_opts} #{payload_fn.path}"
    raise Error, (gpg_output || "gpg command failed: #{cmd}") unless $?.success?

    encrypted_payload = RMail::Message.new
    encrypted_payload.header["Content-Type"] = "application/octet-stream"
    encrypted_payload.header["Content-Disposition"] = 'inline; filename="msg.asc"'
    encrypted_payload.body = gpg_output

    control = RMail::Message.new
    control.header["Content-Type"] = "application/pgp-encrypted"
    control.header["Content-Disposition"] = "attachment"
    control.body = "Version: 1\n"

    envelope = RMail::Message.new
    envelope.header["Content-Type"] = 'multipart/encrypted; protocol="application/pgp-encrypted"'

    envelope.add_part control
    envelope.add_part encrypted_payload
    envelope
  end

  def sign_and_encrypt from, to, payload
    encrypt from, to, payload, true
  end

  def verify payload, signature # both RubyMail::Message objects
    return unknown_status(cant_find_binary) unless @cmd

    payload_fn = Tempfile.new "redwood.payload"
    payload_fn.write format_payload(payload)
    payload_fn.close

    signature_fn = Tempfile.new "redwood.signature"
    signature_fn.write signature.decode
    signature_fn.close

    output = run_gpg "--verify #{signature_fn.path} #{payload_fn.path}"
    output_lines = output.split(/\n/)

    if output =~ /^gpg: (.* signature from .*$)/
      if $? == 0
        Chunk::CryptoNotice.new :valid, $1, output_lines
      else
        Chunk::CryptoNotice.new :invalid, $1, output_lines
      end
    else
      unknown_status output_lines
    end
  end

  ## returns decrypted_message, status, desc, lines
  def decrypt payload # a RubyMail::Message object
    return unknown_status(cant_find_binary) unless @cmd

    payload_fn = Tempfile.new "redwood.payload"
    payload_fn.write payload.to_s
    payload_fn.close

    output = run_gpg "--decrypt #{payload_fn.path}"

    if $?.success?
      decrypted_payload, sig_lines =
        if output =~ /\A(.*?)((^gpg: .*$)+)\Z/m
          [$1, $2]
        else
          [output, nil]
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
      notice = Chunk::CryptoNotice.new :invalid, "This message could not be decrypted", output.split("\n")
      [nil, nil, notice]
    end
  end

private

  def unknown_status lines=[]
    Chunk::CryptoNotice.new :unknown, "Unable to determine validity of cryptographic signature", lines
  end
  
  def cant_find_binary
    ["Can't find gpg binary in path."]
  end

  ## here's where we munge rmail output into the format that signed/encrypted
  ## PGP/GPG messages should be
  def format_payload payload
    payload.to_s.gsub(/(^|[^\r])\n/, "\\1\r\n").gsub(/^MIME-Version: .*\r\n/, "")
  end

  def run_gpg args
    cmd = "#{@cmd} #{args} 2> /dev/null"
    #Redwood::log "crypto: running: #{cmd}"
    output = `#{cmd}`
    #Redwood::log "crypto: output: #{output.inspect}" unless $?.success?
    output
  end
end
end
