require "sup/mbox/loader"
require "sup/mbox/ssh-file"
require "sup/mbox/ssh-loader"
require "sup/rfc2047"

module Redwood

## some utility functions. actually these are not mbox-specific at all
## and should be moved somewhere else.
##
## TODO: move functionality to somewhere better, like message.rb
module MBox
  BREAK_RE = /^From \S+/

  def read_header f
    header = {}
    last = nil

    ## i do it in this weird way because i am trying to speed things up
    ## when scanning over large mbox files.
    while(line = f.gets)
      case line
      when /^(From):\s+(.*?)\s*$/i,
        /^(To):\s+(.*?)\s*$/i,
        /^(Cc):\s+(.*?)\s*$/i,
        /^(Bcc):\s+(.*?)\s*$/i,
        /^(Subject):\s+(.*?)\s*$/i,
        /^(Date):\s+(.*?)\s*$/i,
        /^(References):\s+(.*?)\s*$/i,
        /^(In-Reply-To):\s+(.*?)\s*$/i,
        /^(Reply-To):\s+(.*?)\s*$/i,
        /^(List-Post):\s+(.*?)\s*$/i,
        /^(Status):\s+(.*?)\s*$/i: header[last = $1] = $2
      when /^(Message-Id):\s+(.*?)\s*$/i: header[mid_field = last = $1] = $2

      ## these next three can occur multiple times, and we want the
      ## first one
      when /^(Delivered-To):\s+(.*)$/i,
        /^(X-Original-To):\s+(.*)$/i,
        /^(Envelope-To):\s+(.*)$/i: header[last = $1] ||= $2

      when /^$/: break
      when /:/: last = nil # some other header we don't care about
      else
        header[last] += " " + line.chomp.gsub(/^\s+/, "") if last
      end
    end

    if mid_field && header[mid_field] && header[mid_field] =~ /<(.*?)>/
      header[mid_field] = $1
    end

    header.each do |k, v|
      next unless Rfc2047.is_encoded? v
      header[k] =
        begin
          Rfc2047.decode_to $encoding, v
        rescue Errno::EINVAL, Iconv::InvalidEncoding, Iconv::IllegalSequence => e
          Redwood::log "warning: error decoding RFC 2047 header (#{e.class.name}): #{e.message}"
          v
        end
    end
    header
  end
  
  def read_body f
    body = []
    f.each_line do |l|
      break if l =~ BREAK_RE
      body << l.chomp
    end
    body
  end

  module_function :read_header, :read_body
end
end
