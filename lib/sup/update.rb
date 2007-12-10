module Redwood

## Classic listener/sender paradigm. Handles communication between various
## parts of Sup.
##
## Usage note: don't pass threads around. Neither thread nor message equality
## is defined beyond standard object equality. For Thread equality, this is
## because of computational cost. But message equality is trivial by comparing
## message ids, so to communicate something about a particular thread, just
## pass a representative message from it instead.
##
## This assumes that no message will be a part of more than one thread within
## a single "view" (otherwise a message from a thread wouldn't uniquely
## identify it). But that's true.

class UpdateManager
  include Singleton

  def initialize
    @targets = {}
    self.class.i_am_the_instance self
  end

  def register o; @targets[o] = true; end
  def unregister o; @targets.delete o; end

  def relay sender, type, *args
    meth = "handle_#{type}_update".intern
    @targets.keys.each { |o| o.send meth, sender, *args unless o == sender if o.respond_to? meth }
  end
end

end
