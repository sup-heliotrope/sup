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
require 'sup/util'
require 'sup/hook'
require 'sup/contact'
require 'sup/person'
require 'sup/account'
require 'sup/crypto'
require 'stringio'

module Redwood

# These are all singletons
CryptoManager.init
Dir.mktmpdir('sup-test') do|f|
    HookManager.init f
end
am = {:default=> {:name => "bob", :email=>"bob@foo.nowhere"}}
AccountManager.init am
print CryptoManager.have_crypto?

class TestCryptoManager < Test::Unit::TestCase

    def setup
    end

    def teardown
    end

    def test_sign
        if CryptoManager.have_crypto? then
            signed = CryptoManager.sign "bob@foo.nowhere","alice@bar.anywhere","ABCDEFG"
            assert_instance_of RMail::Message, signed
        end
    end


    def test_encrypt
        if CryptoManager.have_crypto? then
            from_email = Person.from_address("bob@foo.nowhere").email
            to_email = Person.from_address("alice@bar.anywhere").email

            encrypted = CryptoManager.encrypt from_email, [to_email], "ABCDEFG"
            assert_instance_of RMail::Message, encrypted
        end
    end

        
end

end
