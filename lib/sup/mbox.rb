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
  BREAK_RE = /^From \S+/ ######### TODO REMOVE ME

  ## WARNING! THIS IS A SPEED-CRITICAL SECTION. Everything you do here will have
  ## a significant effect on Sup's processing speed of email from ALL sources.
  ## Little things like string interpolation, regexp interpolation, += vs <<,
  ## all have DRAMATIC effects. BE CAREFUL WHAT YOU DO!
  def read_header f
    header = {}
    last = nil

    while(line = f.gets)
      case line
      ## these three can occur multiple times, and we want the first one
      when /^(Delivered-To|X-Original-To|Envelope-To):\s*(.*?)\s*$/i; header[last = $1.downcase] ||= $2
      ## mark this guy specially. not sure why i care.
      when /^([^:\s]+):\s*(.*?)\s*$/i; header[last = $1.downcase] = $2
      when /^\r*$/; break
      else
        if last
          header[last] << " " unless header[last].empty?
          header[last] << line.strip
        end
      end
    end

    %w(subject from to cc bcc).each do |k|
      v = header[k] or next
      next unless Rfc2047.is_encoded? v
      header[k] = begin
        Rfc2047.decode_to $encoding, v
      rescue Errno::EINVAL, Iconv::InvalidEncoding, Iconv::IllegalSequence => e
        Redwood::log "warning: error decoding RFC 2047 header (#{e.class.name}): #{e.message}"
        v
      end
    end
    header
  end
  
  module_function :read_header
end
end
