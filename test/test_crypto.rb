#!/usr/bin/ruby

# tests for sup's crypto libs
#
# Copyright Clint Byrum <clint@ubuntu.com> 2011. All Rights Reserved.
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

require 'tmpdir'
require 'test/unit'
require 'rmail/message'
require 'rmail/parser'
require 'sup/util'
require 'sup/hook'
require 'sup/contact'
require 'sup/person'
require 'sup/account'
require 'sup/message-chunks'
require 'sup/crypto'
require 'stringio'

module Redwood

# These are all singletons
CryptoManager.init
Dir.mktmpdir('sup-test') do|f|
    HookManager.init f
end
am = {:default=> {:name => "", :email=>ENV['EMAIL']}}
AccountManager.init am

class TestCryptoManager < Test::Unit::TestCase

    def setup
        @from_email = ENV['EMAIL']
        # Change this or import my public key to make these tests work.
        @to_email = 'clint@ubuntu.com'
    end

    def teardown
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
        
end

end
