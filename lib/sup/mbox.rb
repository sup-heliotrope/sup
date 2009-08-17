require "sup/mbox/loader"
require "sup/mbox/ssh-file"
require "sup/mbox/ssh-loader"

module Redwood

module MBox
  BREAK_RE = /^From \S+ (.+)$/

  def is_break_line? l
    l =~ BREAK_RE or return false
    time = $1
    begin
      ## hack -- make Time.parse fail when trying to substitute values from Time.now
      Time.parse time, 0
      true
    rescue NoMethodError
      warn "found invalid date in potential mbox split line, not splitting: #{l.inspect}"
      false
    end
  end
  module_function :is_break_line?
end
end
