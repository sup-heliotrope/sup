# tests for sup's crypto libs
#
# Copyright Clint Byrum <clint@ubuntu.com> 2011. All Rights Reserved.
# Copyright Sup Developers                 2013.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.

require 'test_helper'
require 'sup'
require 'stringio'
require 'tmpdir'

module Redwood

class TestCryptoManager < Minitest::Test

    def setup
        @from_email = 'sup-test-1@foo.bar'
        @from_email_ecc = 'sup-fake-ecc@fake.fake'
        @to_email   = 'sup-test-2@foo.bar'
        # Use test gnupg setup
        @orig_gnupghome = ENV['GNUPGHOME']
        ENV['GNUPGHOME'] = File.join(File.dirname(__FILE__), 'gnupg_test_home')

        @path = Dir.mktmpdir
        Redwood::HookManager.init File.join(@path, 'hooks')

        account = {
          :name => +"test",
          :email => @from_email.dup,
          :alternates => [@from_email_ecc.dup],
          :sendmail => "/bin/false",
        }
        Redwood::AccountManager.init :default => account

        Redwood::CryptoManager.init
    end

    def teardown
      CryptoManager.deinstantiate!
      AccountManager.deinstantiate!
      HookManager.deinstantiate!
      FileUtils.rm_r @path

      ENV['GNUPGHOME'] = @orig_gnupghome
    end

    def test_sign
      skip CryptoManager.not_working_reason if not CryptoManager.have_crypto?

      signed = CryptoManager.sign @from_email,@to_email,"ABCDEFG"
      assert_instance_of RMail::Message, signed
      assert_equal("multipart/signed; protocol=application/pgp-signature; micalg=pgp-sha256",
                   signed.header["Content-Type"])
      assert_equal "ABCDEFG", signed.body[0]
      assert signed.body[1].body.length > 0 , "signature length must be > 0"
      assert (signed.body[1].body.include? "-----BEGIN PGP SIGNATURE-----") , "Expecting PGP armored data"
    end

    def test_sign_nested_parts
      skip CryptoManager.not_working_reason if not CryptoManager.have_crypto?

      body = RMail::Message.new
      body.header["Content-Disposition"] = +"inline"
      body.body = "ABCDEFG"
      payload = RMail::Message.new
      payload.header["MIME-Version"] = +"1.0"
      payload.add_part body
      payload.add_part RMail::Message.make_attachment "attachment", "text/plain", nil, "attachment.txt"
      signed = CryptoManager.sign @from_email, @to_email, payload
      ## The result is a multipart/signed containing a multipart/mixed.
      ## There should be a MIME-Version header on the top-level
      ## multipart/signed message, but *not* on the enclosed
      ## multipart/mixed part.
      assert_equal 1, signed.to_s.scan(/MIME-Version:/).size
    end

    def test_encrypt
      skip CryptoManager.not_working_reason if not CryptoManager.have_crypto?

      encrypted = CryptoManager.encrypt @from_email, [@to_email], "ABCDEFG"
      assert_instance_of RMail::Message, encrypted
      assert (encrypted.body[1].body.include? "-----BEGIN PGP MESSAGE-----") , "Expecting PGP armored data"
    end

    def test_sign_and_encrypt
      skip CryptoManager.not_working_reason if not CryptoManager.have_crypto?

      encrypted = CryptoManager.sign_and_encrypt @from_email, [@to_email], "ABCDEFG"
      assert_instance_of RMail::Message, encrypted
      assert (encrypted.body[1].body.include? "-----BEGIN PGP MESSAGE-----") , "Expecting PGP armored data"
    end

    def test_decrypt
      skip CryptoManager.not_working_reason if not CryptoManager.have_crypto?

      encrypted = CryptoManager.encrypt @from_email, [@to_email], "ABCDEFG"
      assert_instance_of RMail::Message, encrypted
      assert_instance_of String, (encrypted.body[1].body)
      decrypted = CryptoManager.decrypt encrypted.body[1], true
      assert_instance_of Array, decrypted
      assert_instance_of Chunk::CryptoNotice, decrypted[0]
      assert_instance_of Chunk::CryptoNotice, decrypted[1]
      assert_instance_of RMail::Message, decrypted[2]
      assert_equal "ABCDEFG" , decrypted[2].body
    end

    def test_decrypt_and_verify
      skip CryptoManager.not_working_reason if not CryptoManager.have_crypto?

      encrypted = CryptoManager.sign_and_encrypt @from_email, [@to_email], "ABCDEFG"
      assert_instance_of RMail::Message, encrypted
      assert_instance_of String, (encrypted.body[1].body)
      decrypted = CryptoManager.decrypt encrypted.body[1], true
      assert_instance_of Array, decrypted
      assert_instance_of Chunk::CryptoNotice, decrypted[0]
      assert_instance_of Chunk::CryptoNotice, decrypted[1]
      assert_instance_of RMail::Message, decrypted[2]
      assert_match(/^Signature made .* using RSA key ID 072B50BE/,
                   decrypted[1].lines[0])
      assert_equal "Good signature from \"#{@from_email}\"", decrypted[1].lines[1]
      assert_equal "ABCDEFG" , decrypted[2].body
    end

    def test_decrypt_and_verify_nondefault_key
      skip CryptoManager.not_working_reason if not CryptoManager.have_crypto?

      encrypted = CryptoManager.sign_and_encrypt @from_email_ecc, [@to_email], "ABCDEFG"
      assert_instance_of RMail::Message, encrypted
      assert_instance_of String, (encrypted.body[1].body)
      decrypted = CryptoManager.decrypt encrypted.body[1], true
      assert_instance_of Array, decrypted
      assert_instance_of Chunk::CryptoNotice, decrypted[0]
      assert_instance_of Chunk::CryptoNotice, decrypted[1]
      assert_instance_of RMail::Message, decrypted[2]
      assert_match(/^Signature made .* key ID AC34B83C/, decrypted[1].lines[0])
      assert_equal "Good signature from \"#{@from_email_ecc}\"", decrypted[1].lines[1]
      assert_equal "ABCDEFG" , decrypted[2].body
    end

    def test_verify
      skip CryptoManager.not_working_reason if not CryptoManager.have_crypto?

      signed = CryptoManager.sign @from_email, @to_email, "ABCDEFG"
      assert_instance_of RMail::Message, signed
      assert_instance_of String, (signed.body[1].body)
      chunk = CryptoManager.verify signed.body[0], signed.body[1], true
      assert_instance_of Redwood::Chunk::CryptoNotice, chunk
      assert_match(/^Signature made .* using RSA key ID 072B50BE/,
                   chunk.lines[0])
      assert_equal "Good signature from \"#{@from_email}\"", chunk.lines[1]
    end

    def test_verify_unknown_keytype
      skip CryptoManager.not_working_reason if not CryptoManager.have_crypto?

      signed = CryptoManager.sign @from_email_ecc, @to_email, "ABCDEFG"
      assert_instance_of RMail::Message, signed
      assert_instance_of String, (signed.body[1].body)
      chunk = CryptoManager.verify signed.body[0], signed.body[1], true
      assert_instance_of Redwood::Chunk::CryptoNotice, chunk
      assert_match(/^Signature made .* using unknown key type \(303\) key ID AC34B83C/,
                   chunk.lines[0])
      assert_equal "Good signature from \"#{@from_email_ecc}\"", chunk.lines[1]
    end

    def test_verify_nested_parts
      skip CryptoManager.not_working_reason if not CryptoManager.have_crypto?

      ## Generate a multipart/signed containing a multipart/mixed.
      ## We will test verifying the generated signature below.
      ## Importantly, the inner multipart/mixed does *not* have a
      ## MIME-Version header because it is not a top-level message.
      payload = RMail::Parser.read <<EOS
Content-Type: multipart/mixed; boundary="=-1652088224-7794-561531-1825-1-="


--=-1652088224-7794-561531-1825-1-=
Content-Disposition: inline

ABCDEFG
--=-1652088224-7794-561531-1825-1-=
Content-Disposition: attachment; filename="attachment.txt"
Content-Type: text/plain; name="attachment.txt"

attachment
--=-1652088224-7794-561531-1825-1-=--
EOS
      signed = CryptoManager.sign @from_email_ecc, @to_email, payload
      CryptoManager.verify payload, signed.body[1], true
    end
end

end
