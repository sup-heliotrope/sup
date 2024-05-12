#!/usr/bin/ruby

require 'sup'
require 'stringio'
require 'rmail'
require 'uri'

module Redwood

class DummySource < Source

  attr_accessor :messages
  attr_writer :fallback_date

  def initialize uri, last_date=nil, usual=true, archived=false, id=nil, labels=[]
    super uri, usual, archived, id
    @messages = nil
    @fallback_date = Time.utc 2001, 2, 3, 4, 56, 57
  end

  def start_offset
    0
  end

  def end_offset
    # should contain the number of test messages -1
    return @messages ? @messages.length - 1 : 0
  end

  def with_file_for id
    fn = @messages[id]
    File.open(fn, 'rb') { |f| yield f }
  end

  def load_header id
    with_file_for(id) { |f| parse_raw_email_header f }
  end

  def load_message id
    with_file_for(id) { |f| RMail::Parser.read f }
  end

  def raw_header id
    ret = ""
    with_file_for(id) do |f|
      until f.eof? || (l = f.gets) =~ /^$/
        ret += l
      end
    end
    ret
  end

  def raw_message id
    with_file_for(id) { |f| f.read }
  end

  def each_raw_message_line id
    with_file_for(id) do |f|
      until f.eof?
        yield f.gets
      end
    end
  end

  def fallback_date_for_message id
    @fallback_date
  end
end

end

# vim:noai:ts=2:sw=2:

