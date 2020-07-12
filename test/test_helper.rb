require "rubygems" rescue nil
require 'minitest/autorun'
require "rr"

def fixture_path(filename)
  File.expand_path("../fixtures/#{filename}", __FILE__)
end

def fixture_contents(filename)
  file = ''
  File.open(fixture_path(filename)) { |io| file = io.read }
  file
end
