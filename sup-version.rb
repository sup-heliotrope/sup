## allow people who use development versions by running "rake gem"
## and installing the resulting gem it to be able to do this. (gem
## versions must be in dotted-digit notation only and can be passed
## with the REL environment variable to "rake gem").
SUP_VERSION = if ENV['REL']
  ENV['REL']
else
  $:.unshift 'lib' # force loading from ./lib/ if it exists
  require 'sup'
  if Redwood::VERSION == "git"
    "999"
  else
    Redwood::VERSION
  end
end
