module Redwood

## Implements a single undo list for the Sup instance
##
## The basic idea is to keep a list of lambdas to undo
## things. When an action is called (such as 'archive'),
## a lambda is registered with UndoManager that will
## undo the archival action

class UndoManager
  include Singleton

  def initialize
    @@actionlist = []
    self.class.i_am_the_instance self
  end

  def register desc, actions
    actions = [actions] unless actions.is_a?Array
    raise StandardError, "when would I need to undo 'nothing?'" unless actions.length > 0
    Redwood::log "registering #{actions.length} actions: #{desc}"
    @@actionlist.push({:desc => desc, :actions => actions})
  end

  def undo
    unless @@actionlist.length == 0 then
      actionset = @@actionlist.pop
      Redwood::log "undoing #{actionset[:desc]}..."
      actionset[:actions].each{|action|
        action.call
      }
      BufferManager.flash "undid #{actionset[:desc]}"
    else
      BufferManager.flash "nothing more to undo"
    end
  end

  def clear
    @@actionlist = []
  end
end
end
