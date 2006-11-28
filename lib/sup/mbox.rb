require "sup/mbox/loader"

module Redwood

## some utility functions
module MBox
  BREAK_RE = /^From \S+@\S+/

  def read_header f
    header = {}
    last = nil

    ## i do it in this weird way because i am trying to speed things up
    ## at load-message time.
    while(line = f.gets)
      case line
      when /^From:\s+(.*)$/i: header[last = "From"] = $1
      when /^To:\s+(.*)$/i: header[last = "To"] = $1
      when /^Cc:\s+(.*)$/i: header[last = "Cc"] = $1
      when /^Bcc:\s+(.*)$/i: header[last = "Bcc"] = $1
      when /^Subject:\s+(.*)$/i: header[last = "Subject"] = $1
      when /^Date:\s+(.*)$/i: header[last = "Date"] = $1
      when /^Message-Id:\s+<(.*)>$/i: header[last = "Message-Id"] = $1
      when /^References:\s+(.*)$/i: header[last = "References"] = $1
      when /^In-Reply-To:\s+(.*)$/i: header[last = "In-Reply-To"] = $1
      when /^List-Post:\s+(.*)$/i: header[last = "List-Post"] = $1
      when /^Reply-To:\s+(.*)$/i: header[last = "Reply-To"] = $1
      when /^Status:\s+(.*)$/i: header[last = "Status"] = $1
      when /^Delivered-To:\s+(.*)$/i
        header[last = "Delivered-To"] = $1 unless header["Delivered-To"]
      when /^$/: break
      when /:/: last = nil
      else
        header[last] += line.gsub(/^\s+/, "") if last
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
