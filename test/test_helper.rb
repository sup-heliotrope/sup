require "rubygems" rescue nil
require 'minitest/autorun'
require "rr"

class Minitest::Unit::TestCase
  include ::RR::Adapters::MiniTest
end
