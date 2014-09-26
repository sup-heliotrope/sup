require "test_helper"
require "test_header_parsing"

# verify that an mbox with special characters in the URI work normally
# piggybacking on existing mbox tests
class TestMBoxParsingSpecial < TestMBoxParsing
  def setup
    @path = Dir.mktmpdir
    @mbox = File.join(@path, "test#{URI_ENCODE_CHARS}.mbox")
  end
end

