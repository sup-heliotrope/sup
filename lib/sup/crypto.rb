begin
  require 'gpgme'
rescue LoadError
end

module Redwood

class CryptoManager
  include Redwood::Singleton

  class Error < StandardError; end

  OUTGOING_MESSAGE_OPERATIONS = {
    sign: "Sign",
    sign_and_encrypt: "Sign and encrypt",
    encrypt: "Encrypt only"
  }

  KEY_PATTERN = /(-----BEGIN PGP PUBLIC KEY BLOCK.*-----END PGP PUBLIC KEY BLOCK)/m
  KEYSERVER_URL = "http://pool.sks-keyservers.net:11371/pks/lookup"

  HookManager.register "gpg-options", <<EOS
Runs before gpg is called, allowing you to modify the options (most
likely you would want to add something to certain commands, like
{:always_trust => true} to encrypting a message, but who knows).

Variables:
operation: what operation will be done ("sign", "encrypt", "decrypt" or "verify")
options: a dictionary of values to be passed to GPGME

Return value: a dictionary to be passed to GPGME
EOS

  HookManager.register "sig-output", <<EOS
Runs when the signature output is being generated, allowing you to
add extra information to your signatures if you want.

Variables:
signature: the signature object (class is GPGME::Signature)
from_key: the key that generated the signature (class is GPGME::Key)

Return value: an array of lines of output
EOS

  HookManager.register "gpg-expand-keys", <<EOS
Runs when the list of encryption recipients is created, allowing you to
replace a recipient with one or more GPGME recipients. For example, you could
replace the email address of a mailing list with the key IDs that belong to
the recipients of that list. This is essentially what GPG groups do, which
are not supported by GPGME.

Variables:
recipients: an array of recipients of the current email

Return value: an array of recipients (email address or GPG key ID) to encrypt
the email for
EOS

  def initialize
    @mutex = Mutex.new

    @not_working_reason = nil

    # test if the gpgme gem is available
    @gpgme_present =
      begin
        begin
          begin
            GPGME.check_version({:protocol => GPGME::PROTOCOL_OpenPGP})
          rescue TypeError
            GPGME.check_version(nil)
          end
          true
        rescue GPGME::Error
          false
        rescue ArgumentError
          # gpgme 2.0.0 raises this due to the hash->string conversion
          false
        end
      rescue NameError
        false
      end

    unless @gpgme_present
      @not_working_reason = ['gpgme gem not present',
        'Install the gpgme gem in order to use signed and encrypted emails']
      return
    end

    # if gpg2 is available, it will start gpg-agent if required
    if (bin = `which gpg2`.chomp) =~ /\S/
      if GPGME.respond_to?('set_engine_info')
        GPGME.set_engine_info GPGME::PROTOCOL_OpenPGP, bin, nil
      else
        GPGME.gpgme_set_engine_info GPGME::PROTOCOL_OpenPGP, bin, nil
      end
    else
      # check if the gpg-options hook uses the passphrase_callback
      # if it doesn't then check if gpg agent is present
      gpg_opts = HookManager.run("gpg-options",
                               {:operation => "sign", :options => {}}) || {}
      if gpg_opts[:passphrase_callback].nil?
        if ENV['GPG_AGENT_INFO'].nil?
          @not_working_reason = ["Environment variable 'GPG_AGENT_INFO' not set, is gpg-agent running?",
                             "If gpg-agent is running, try $ export `cat ~/.gpg-agent-info`"]
          return
        end

        gpg_agent_socket_file = ENV['GPG_AGENT_INFO'].split(':')[0]
        unless File.exist?(gpg_agent_socket_file)
          @not_working_reason = ["gpg-agent socket file #{gpg_agent_socket_file} does not exist"]
          return
        end

        s = File.stat(gpg_agent_socket_file)
        unless s.socket?
          @not_working_reason = ["gpg-agent socket file #{gpg_agent_socket_file} is not a socket"]
          return
        end
      end
    end
  end

  def have_crypto?; @not_working_reason.nil? end
  def not_working_reason; @not_working_reason end

  def sign from, to, payload
    return unknown_status(@not_working_reason) unless @not_working_reason.nil?

    gpg_opts = {:protocol => GPGME::PROTOCOL_OpenPGP, :armor => true, :textmode => true}
    gpg_opts.merge!(gen_sign_user_opts(from))
    gpg_opts = HookManager.run("gpg-options",
                               {:operation => "sign", :options => gpg_opts}) || gpg_opts
    begin
      if GPGME.respond_to?('detach_sign')
        sig = GPGME.detach_sign(format_payload(payload), gpg_opts)
      else
        crypto = GPGME::Crypto.new
        gpg_opts[:mode] = GPGME::SIG_MODE_DETACH
        sig = crypto.sign(format_payload(payload), gpg_opts).read
      end
    rescue GPGME::Error => exc
      raise Error, gpgme_exc_msg(exc.message)
    end

    # if the key (or gpg-agent) is not available GPGME does not complain
    # but just returns a zero length string. Let's catch that
    if sig.length == 0
      raise Error, gpgme_exc_msg("GPG failed to generate signature: check that gpg-agent is running and your key is available.")
    end

    envelope = RMail::Message.new
    envelope.header["Content-Type"] = 'multipart/signed; protocol=application/pgp-signature'

    envelope.add_part payload
    signature = RMail::Message.make_attachment sig, "application/pgp-signature", nil, "signature.asc"
    envelope.add_part signature
    envelope
  end

  def encrypt from, to, payload, sign=false
    return unknown_status(@not_working_reason) unless @not_working_reason.nil?

    gpg_opts = {:protocol => GPGME::PROTOCOL_OpenPGP, :armor => true, :textmode => true}
    if sign
      gpg_opts.merge!(gen_sign_user_opts(from))
      gpg_opts.merge!({:sign => true})
    end
    gpg_opts = HookManager.run("gpg-options",
                               {:operation => "encrypt", :options => gpg_opts}) || gpg_opts
    recipients = to + [from]
    recipients = HookManager.run("gpg-expand-keys", { :recipients => recipients }) || recipients
    begin
      if GPGME.respond_to?('encrypt')
        cipher = GPGME.encrypt(recipients, format_payload(payload), gpg_opts)
      else
        crypto = GPGME::Crypto.new
        gpg_opts[:recipients] = recipients
        cipher = crypto.encrypt(format_payload(payload), gpg_opts).read
      end
    rescue GPGME::Error => exc
      raise Error, gpgme_exc_msg(exc.message)
    end

    # if the key (or gpg-agent) is not available GPGME does not complain
    # but just returns a zero length string. Let's catch that
    if cipher.length == 0
      raise Error, gpgme_exc_msg("GPG failed to generate cipher text: check that gpg-agent is running and your key is available.")
    end

    encrypted_payload = RMail::Message.new
    encrypted_payload.header["Content-Type"] = "application/octet-stream"
    encrypted_payload.header["Content-Disposition"] = 'inline; filename="msg.asc"'
    encrypted_payload.body = cipher

    control = RMail::Message.new
    control.header["Content-Type"] = "application/pgp-encrypted"
    control.header["Content-Disposition"] = "attachment"
    control.body = "Version: 1\n"

    envelope = RMail::Message.new
    envelope.header["Content-Type"] = 'multipart/encrypted; protocol=application/pgp-encrypted'

    envelope.add_part control
    envelope.add_part encrypted_payload
    envelope
  end

  def sign_and_encrypt from, to, payload
    encrypt from, to, payload, true
  end

  def verified_ok? verify_result
    valid = true
    unknown = false
    all_output_lines = []
    all_trusted = true
    unknown_fingerprint = nil

    verify_result.signatures.each do |signature|
      output_lines, trusted, unknown_fingerprint = sig_output_lines signature
      all_output_lines << output_lines
      all_output_lines.flatten!
      all_trusted &&= trusted

      err_code = GPGME::gpgme_err_code(signature.status)
      if err_code == GPGME::GPG_ERR_BAD_SIGNATURE
        valid = false
      elsif err_code != GPGME::GPG_ERR_NO_ERROR
        valid = false
        unknown = true
      end
    end

    if valid || !unknown
      summary_line = simplify_sig_line(verify_result.signatures[0].to_s, all_trusted)
    end

    if all_output_lines.length == 0
      Chunk::CryptoNotice.new :valid, "Encrypted message wasn't signed", all_output_lines
    elsif valid
      if all_trusted
        Chunk::CryptoNotice.new(:valid, summary_line, all_output_lines)
      else
        Chunk::CryptoNotice.new(:valid_untrusted, summary_line, all_output_lines)
      end
    elsif !unknown
      Chunk::CryptoNotice.new(:invalid, summary_line, all_output_lines)
    elsif unknown_fingerprint
      Chunk::CryptoNotice.new(:unknown_key, "Unable to determine validity of cryptographic signature", all_output_lines, unknown_fingerprint)
    else
      unknown_status all_output_lines
    end
  end

  def verify payload, signature, detached=true # both RubyMail::Message objects
    return unknown_status(@not_working_reason) unless @not_working_reason.nil?

    gpg_opts = {:protocol => GPGME::PROTOCOL_OpenPGP}
    gpg_opts = HookManager.run("gpg-options",
                               {:operation => "verify", :options => gpg_opts}) || gpg_opts
    ctx = GPGME::Ctx.new(gpg_opts)
    sig_data = GPGME::Data.from_str signature.decode
    if detached
      signed_text_data = GPGME::Data.from_str(format_payload(payload))
      plain_data = nil
    else
      signed_text_data = nil
      if GPGME::Data.respond_to?('empty')
        plain_data = GPGME::Data.empty
      else
        plain_data = GPGME::Data.empty!
      end
    end
    begin
      ctx.verify(sig_data, signed_text_data, plain_data)
    rescue GPGME::Error => exc
      return unknown_status [gpgme_exc_msg(exc.message)]
    end
    begin
      self.verified_ok? ctx.verify_result
    rescue ArgumentError => exc
      return unknown_status [gpgme_exc_msg(exc.message)]
    end
  end

  ## returns decrypted_message, status, desc, lines
  def decrypt payload, armor=false # a RubyMail::Message object
    return unknown_status(@not_working_reason) unless @not_working_reason.nil?

    gpg_opts = {:protocol => GPGME::PROTOCOL_OpenPGP}
    gpg_opts = HookManager.run("gpg-options",
                               {:operation => "decrypt", :options => gpg_opts}) || gpg_opts
    ctx = GPGME::Ctx.new(gpg_opts)
    cipher_data = GPGME::Data.from_str(format_payload(payload))
    if GPGME::Data.respond_to?('empty')
      plain_data = GPGME::Data.empty
    else
      plain_data = GPGME::Data.empty!
    end
    begin
      ctx.decrypt_verify(cipher_data, plain_data)
    rescue GPGME::Error => exc
      return Chunk::CryptoNotice.new(:invalid, "This message could not be decrypted", gpgme_exc_msg(exc.message))
    end
    begin
      sig = self.verified_ok? ctx.verify_result
    rescue ArgumentError => exc
      sig = unknown_status [gpgme_exc_msg(exc.message)]
    end
    plain_data.seek(0, IO::SEEK_SET)
    output = plain_data.read
    output.transcode(Encoding::ASCII_8BIT, output.encoding)

    ## TODO: test to see if it is still necessary to do a 2nd run if verify
    ## fails.
    #
    ## check for a valid signature in an extra run because gpg aborts if the
    ## signature cannot be verified (but it is still able to decrypt)
    #sigoutput = run_gpg "#{payload_fn.path}"
    #sig = self.old_verified_ok? sigoutput, $?

    if armor
      msg = RMail::Message.new
      # Look for Charset, they are put before the base64 crypted part
      charsets = payload.body.split("\n").grep(/^Charset:/)
      if !charsets.empty? and charsets[0] =~ /^Charset: (.+)$/
        output.transcode($encoding, $1)
      end
      msg.body = output
    else
      # It appears that some clients use Windows new lines - CRLF - but RMail
      # splits the body and header on "\n\n". So to allow the parse below to
      # succeed, we will convert the newlines to what RMail expects
      output = output.gsub(/\r\n/, "\n")
      # This is gross. This decrypted payload could very well be a multipart
      # element itself, as opposed to a simple payload. For example, a
      # multipart/signed element, like those generated by Mutt when encrypting
      # and signing a message (instead of just clearsigning the body).
      # Supposedly, decrypted_payload being a multipart element ought to work
      # out nicely because Message::multipart_encrypted_to_chunks() runs the
      # decrypted message through message_to_chunks() again to get any
      # children. However, it does not work as intended because these inner
      # payloads need not carry a MIME-Version header, yet they are fed to
      # RMail as a top-level message, for which the MIME-Version header is
      # required. This causes for the part not to be detected as multipart,
      # hence being shown as an attachment. If we detect this is happening,
      # we force the decrypted payload to be interpreted as MIME.
      msg = RMail::Parser.read output
      if msg.header.content_type =~ %r{^multipart/} && !msg.multipart?
        output = "MIME-Version: 1.0\n" + output
        output.fix_encoding!
        msg = RMail::Parser.read output
      end
    end
    notice = Chunk::CryptoNotice.new :valid, "This message has been decrypted for display"
    [notice, sig, msg]
  end

  def retrieve fingerprint
    require 'net/http'
    uri = URI($config[:keyserver_url] || KEYSERVER_URL)
    unless uri.scheme == "http" and not uri.host.nil?
      return "Invalid url: #{uri}"
    end

    fingerprint = "0x" + fingerprint unless fingerprint[0..1] == "0x"
    params = {op: "get", search: fingerprint}
    uri.query = URI.encode_www_form(params)

    begin
      res = Net::HTTP.get_response(uri)
    rescue SocketError # Host doesn't exist or we couldn't connect
    end
    return "Couldn't get key from keyserver at this address: #{uri}" unless res.is_a?(Net::HTTPSuccess)

    match = KEY_PATTERN.match(res.body)
    return "No key found" unless match && match.length > 0

    GPGME::Key.import(match[0])

    return nil
  end

private

  def unknown_status lines=[]
    Chunk::CryptoNotice.new :unknown, "Unable to determine validity of cryptographic signature", lines
  end

  def gpgme_exc_msg msg
    err_msg = "Exception in GPGME call: #{msg}"
    #info err_msg
    err_msg
  end

  ## here's where we munge rmail output into the format that signed/encrypted
  ## PGP/GPG messages should be
  def format_payload payload
    payload.to_s.gsub(/(^|[^\r])\n/, "\\1\r\n")
  end

  # remove the hex key_id and info in ()
  def simplify_sig_line sig_line, trusted
    sig_line.sub!(/from [0-9A-F]{16} /, "from ")
    if !trusted
      sig_line.sub!(/Good signature/, "Good (untrusted) signature")
    end
    sig_line
  end

  def sig_output_lines signature
    # It appears that the signature.to_s call can lead to a EOFError if
    # the key is not found. So start by looking for the key.
    ctx = GPGME::Ctx.new
    begin
      from_key = ctx.get_key(signature.fingerprint)
      if GPGME::gpgme_err_code(signature.status) == GPGME::GPG_ERR_GENERAL
        first_sig = "General error on signature verification for #{signature.fingerprint}"
      elsif signature.to_s
        first_sig = signature.to_s.sub(/from [0-9A-F]{16} /, 'from "') + '"'
      else
        first_sig = "Unknown error or empty signature"
      end
    rescue EOFError
      from_key = nil
      first_sig = "No public key available for #{signature.fingerprint}"
      unknown_fpr = signature.fingerprint
    end

    time_line = "Signature made " + signature.timestamp.strftime("%a %d %b %Y %H:%M:%S %Z") +
                " using " + key_type(from_key, signature.fingerprint) +
                "key ID " + signature.fingerprint[-8..-1]
    output_lines = [time_line, first_sig]

    trusted = false
    if from_key
      # first list all the uids
      if from_key.uids.length > 1
        aka_list = from_key.uids[1..-1]
        aka_list.each { |aka| output_lines << '                aka "' + aka.uid + '"' }
      end

      # now we want to look at the trust of that key
      if signature.validity != GPGME::GPGME_VALIDITY_FULL && signature.validity != GPGME::GPGME_VALIDITY_MARGINAL
        output_lines << "WARNING: This key is not certified with a trusted signature!"
        output_lines << "There is no indication that the signature belongs to the owner"
        output_lines << "Full fingerprint is: " + (0..9).map {|i| signature.fpr[(i*4),4]}.join(":")
      else
        trusted = true
      end

      # finally, run the hook
      output_lines << HookManager.run("sig-output",
                               {:signature => signature, :from_key => from_key})
    end
    return output_lines, trusted, unknown_fpr
  end

  def key_type key, fpr
    return "" if key.nil?
    subkey = key.subkeys.find {|subkey| subkey.fpr == fpr || subkey.keyid == fpr }
    return "" if subkey.nil?

    case subkey.pubkey_algo
    when GPGME::PK_RSA then "RSA "
    when GPGME::PK_DSA then "DSA "
    when GPGME::PK_ELG then "ElGamel "
    when GPGME::PK_ELG_E then "ElGamel "
    else "unknown key type (#{subkey.pubkey_algo}) "
    end
  end

  # logic is:
  # if    gpgkey set for this account, then use that
  # elsif only one account,            then leave blank so gpg default will be user
  # else                                    set --local-user from_email_address
  # NOTE: multiple signers doesn't seem to work with gpgme (2.0.2, 1.0.8)
  #
  def gen_sign_user_opts from
    account = AccountManager.account_for from
    account ||= AccountManager.default_account
    if !account.gpgkey.nil?
      opts = {:signer => account.gpgkey}
    elsif AccountManager.user_emails.length == 1
      # only one account
      opts = {}
    else
      opts = {:signer => from}
    end
    opts
  end
end
end
