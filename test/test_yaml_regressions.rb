require 'test/unit'

# Requiring 'yaml' before 'sup' in 1.9.x would get Psych loaded first
# and becoming the default yamler.
require 'yaml'
require 'sup'

module Redwood
  class TestYamlRegressions < Test::Unit::TestCase
    def test_yamling_hash
      hsh = {:foo => 42}
      reloaded = YAML.load(hsh.to_yaml)

      assert_equal reloaded, hsh
    end
  end
end
