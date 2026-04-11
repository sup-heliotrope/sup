require 'test_helper'
require 'sup'
require 'sup/contact'

module Redwood

class TestContact < Minitest::Test
  def setup
    @contact = ContactManager.init(File.expand_path("../../fixtures/contacts.txt", __FILE__))
    @person  = Person.new (+"Terrible Name"), (+"terrible@name.com")
  end

  def teardown
    runner = Redwood.const_get "ContactManager".to_sym
    runner.deinstantiate!
  end

  def test_contact_manager
    assert @contact

    ## 2 contacts are imported from the fixture file.
    assert_equal 2, @contact.contacts.count

    rc = @contact.contact_for "RC"
    assert_equal "Random Contact", rc.name
    assert @contact.is_aliased_contact? rc
    assert_equal "RC", @contact.alias_for(rc)

    uc = @contact.person_for "unaliased@example.invalid"
    refute @contact.is_aliased_contact? uc
    assert_nil @contact.alias_for uc
    assert_equal [rc, uc], @contact.contacts
    assert_equal [rc], @contact.contacts_with_aliases

    assert_nil @contact.contact_for "TN"
    @contact.update_alias @person, "TN"

    assert @contact.is_aliased_contact?(@person)
    assert_equal @person, @contact.contact_for("TN")

    assert_equal "TN", @contact.alias_for(@person)
  end
end

end