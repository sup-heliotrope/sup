module Redwood
  ## Implements a single undo list for the Sup instance
  ##
  ## The basic idea is to keep a list of lambdas to undo
  ## things. When an action is called (such as 'archive'),
  ## a lambda is registered with UndoManager that will
  ## undo the archival action

  class UndoManager
    include Redwood::Singleton

    def initialize
      @@actionlist = []
    end

    def register(desc, *actions, &b)
      actions = [*actions.flatten]
      actions << b if b
      fail ArgumentError, 'need at least one action' unless actions.length > 0
      @@actionlist.push desc: desc, actions: actions
    end

    def undo
      if @@actionlist.empty?
        BufferManager.flash 'nothing more to undo!'
      else
        actionset = @@actionlist.pop
        actionset[:actions].each(&:call)
        BufferManager.flash "undid #{actionset[:desc]}"
      end
    end

    def clear
      @@actionlist = []
    end
  end
end
