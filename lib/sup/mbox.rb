require "sup/mbox/loader"
require "sup/mbox/ssh-file"
require "sup/mbox/ssh-loader"

module Redwood

## some utility functions
module MBox
  BREAK_RE = /^From \S+/

  def read_header f
    header = {}
    last = nil

    ## i do it in this weird way because i am trying to speed things up
    ## when scanning over large mbox files.
    while(line = f.gets)
      case line
      when /^(From):\s+(.*)$/i,
        /^(To):\s+(.*)$/i,
        /^(Cc):\s+(.*)$/i,
        /^(Bcc):\s+(.*)$/i,
        /^(Subject):\s+(.*)$/i,
        /^(Date):\s+(.*)$/i,
        /^(Message-Id):\s+<(.*)>$/i,
        /^(References):\s+(.*)$/i,
        /^(In-Reply-To):\s+(.*)$/i,
        /^(Reply-To):\s+(.*)$/i,
        /^(List-Post):\s+(.*)$/i,
        /^(Status):\s+(.*)$/i: header[last = $1] = $2

      ## these next three can occur multiple times, and we want the
      ## first one
      when /^(Delivered-To):\s+(.*)$/i,
        /^(X-Original-To):\s+(.*)$/i,
        /^(Envelope-To):\s+(.*)$/i: header[last = $1.downcase] ||= $2

      when /^$/: break
      when /:/: last = nil
      else
        header[last] += line.chomp.gsub(/^\s+/, "") if last
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
