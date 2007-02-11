module Redwood

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
