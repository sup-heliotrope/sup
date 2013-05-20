# TODO: this is ugly. It's better to have a application singleton passed
# down to lower level components instead of including logging methods in
# class `Object'
#
# For now this is what we have to do.
require "sup/logger"
Redwood::Logger.init.add_sink $stderr
class Object
  include Redwood::LogsStuff
end
