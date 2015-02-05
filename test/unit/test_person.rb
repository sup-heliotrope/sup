require 'test_helper'
require 'sup'

module Redwood

class TestPerson < Minitest::Test
  def setup
    @person = Person.new("Thomassen, Bob", "bob@thomassen.com")
    @no_name = Person.new(nil, "alice@alice.com")
  end

  def test_email_must_be_supplied
    assert_raises (ArgumentError) { Person.new("Alice", nil) }
  end

  def test_to_string
    assert_equal "Thomassen, Bob <bob@thomassen.com>", "#{@person}"
    assert_equal "alice@alice.com", "#{@no_name}"
  end

  def test_shortname
    assert_equal "Bob", @person.shortname
    assert_equal "alice@alice.com", @no_name.shortname
  end

  def test_mediumname
    assert_equal "Thomassen, Bob", @person.mediumname
    assert_equal "alice@alice.com", @no_name.mediumname
  end

  def test_fullname
    assert_equal "\"Thomassen, Bob\" <bob@thomassen.com>", @person.full_address
    assert_equal "alice@alice.com", @no_name.full_address
  end
end

end