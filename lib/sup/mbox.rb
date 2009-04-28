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
  BREAK_RE = /^From \S+@\S+ /
  HEADER_RE = /\s*(.*?)\s*/

  def read_header f
    header = {}
    last = nil

    ## i do it in this weird way because i am trying to speed things up
    ## when scanning over large mbox files.
    while(line = f.gets)
      case line
      ## these three can occur multiple times, and we want the first one
      when /^(Delivered-To):#{HEADER_RE}$/i,
        /^(X-Original-To):#{HEADER_RE}$/i,
        /^(Envelope-To):#{HEADER_RE}$/i: header[last = $1] ||= $2

      when /^(From):#{HEADER_RE}$/i,
        /^(To):#{HEADER_RE}$/i,
        /^(Cc):#{HEADER_RE}$/i,
        /^(Bcc):#{HEADER_RE}$/i,
        /^(Subject):#{HEADER_RE}$/i,
        /^(Date):#{HEADER_RE}$/i,
        /^(References):#{HEADER_RE}$/i,
        /^(In-Reply-To):#{HEADER_RE}$/i,
        /^(Reply-To):#{HEADER_RE}$/i,
        /^(List-Post):#{HEADER_RE}$/i,
        /^(List-Subscribe):#{HEADER_RE}$/i,
        /^(List-Unsubscribe):#{HEADER_RE}$/i,
        /^(Status):#{HEADER_RE}$/i,
        /^(X-\S+):#{HEADER_RE}$/: header[last = $1] = $2
      when /^(Message-Id):#{HEADER_RE}$/i: header[mid_field = last = $1] = $2

      when /^\r*$/: break
      when /^\S+:/: last = nil # some other header we don't care about
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
  
  ## never actually called
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
