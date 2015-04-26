require 'test_helper'
require 'sup/util/locale_fiddler'

class TestFiddle < ::Minitest::Unit::TestCase
  # TODO this is a silly test
  def test_fiddle_set_locale
    before = LocaleDummy.setlocale(6, nil).to_s
    after = LocaleDummy.setlocale(6, "").to_s
    assert(before != after, "Expected locale to be fiddled with")
  end
end

class LocaleDummy
  extend LocaleFiddler
end
