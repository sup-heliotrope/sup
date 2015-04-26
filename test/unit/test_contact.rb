require 'test_helper'
require 'sup/contact'

module Redwood

class TestContact < Minitest::Test
  def setup
    @contact = ContactManager.init(File.expand_path("../../fixtures/contacts.txt", __FILE__))
    @person  = Person.new "Terrible Name", "terrible@name.com"
  end

  def teardown
    runner = Redwood.const_get "ContactManager".to_sym
    runner.deinstantiate!
  end

  def test_contact_manager
    assert @contact
    ## 1 contact is imported from the fixture file.
    assert_equal 1, @contact.contacts.count
    assert_equal @contact.contact_for("RC").name, "Random Contact"

    assert_nil @contact.contact_for "TN"
    @contact.update_alias @person, "TN"

    assert @contact.is_aliased_contact?(@person)
    assert_equal @person, @contact.contact_for("TN")

    assert_equal "TN", @contact.alias_for(@person)
  end
end

end