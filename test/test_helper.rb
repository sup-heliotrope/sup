require "rubygems" rescue nil
require 'minitest/autorun'
require "rr"

def fixture(filename)
  file = ''
  path = File.expand_path("../fixtures/#{filename}", __FILE__)
  File.open(path) { |io| file = io.read }
  file
end