require "rubygems" rescue nil
require 'minitest/autorun'
require "rr"
require "tmpdir"
require "fileutils"

def fixture_path(filename)
  File.expand_path("../fixtures/#{filename}", __FILE__)
end

def fixture_contents(filename)
  file = ''
  File.open(fixture_path(filename)) { |io| file = io.read }
  file
end

## Set SUP_BASE to an empty temp dir, so that tests do not accidentally touch ~/.sup.
## This means test_helper must be require'd before sup.
if defined? Redwood::BASE_DIR
  abort "test_helper must be required before sup"
end
test_sup_base = Dir.mktmpdir "sup-base-for-tests"
ENV["SUP_BASE"] = test_sup_base
Minitest.after_run { FileUtils.rm_rf test_sup_base }
