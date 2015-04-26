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

        am = {:default=> {name: "test", email: @from_email, alternates: [@from_email_ecc]}}
        Redwood::AccountManager.init am

        Redwood::CryptoManager.init

        if not CryptoManager.have_crypto?
          warn "No crypto set up, crypto will not be tested. Reason: #{CryptoManager.not_working_reason}"
        end
    end

    def teardown
      CryptoManager.deinstantiate!
      AccountManager.deinstantiate!
      HookManager.deinstantiate!
      FileUtils.rm_r @path

      ENV['GNUPGHOME'] = @orig_gnupghome
    end

    def test_sign
        if CryptoManager.have_crypto? then
            signed = CryptoManager.sign @from_email,@to_email,"ABCDEFG"
            assert_instance_of RMail::Message, signed
            assert_equal "ABCDEFG", signed.body[0]
            assert signed.body[1].body.length > 0 , "signature length must be > 0"
            assert (signed.body[1].body.include? "-----BEGIN PGP SIGNATURE-----") , "Expecting PGP armored data"
        end
    end

    def test_encrypt
        if CryptoManager.have_crypto? then
            encrypted = CryptoManager.encrypt @from_email, [@to_email], "ABCDEFG"
            assert_instance_of RMail::Message, encrypted
            assert (encrypted.body[1].body.include? "-----BEGIN PGP MESSAGE-----") , "Expecting PGP armored data"
        end
    end

    def test_sign_and_encrypt
        if CryptoManager.have_crypto? then
            encrypted = CryptoManager.sign_and_encrypt @from_email, [@to_email], "ABCDEFG"
            assert_instance_of RMail::Message, encrypted
            assert (encrypted.body[1].body.include? "-----BEGIN PGP MESSAGE-----") , "Expecting PGP armored data"
        end
    end

    def test_decrypt
        if CryptoManager.have_crypto? then
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
    end

    def test_verify
        if CryptoManager.have_crypto?
            signed = CryptoManager.sign @from_email, @to_email, "ABCDEFG"
            assert_instance_of RMail::Message, signed
            assert_instance_of String, (signed.body[1].body)
            CryptoManager.verify signed.body[0], signed.body[1], true
        end
    end

    def test_verify_unknown_keytype
        if CryptoManager.have_crypto?
            signed = CryptoManager.sign @from_email_ecc, @to_email, "ABCDEFG"
            assert_instance_of RMail::Message, signed
            assert_instance_of String, (signed.body[1].body)
            CryptoManager.verify signed.body[0], signed.body[1], true
        end
    end
end

end
