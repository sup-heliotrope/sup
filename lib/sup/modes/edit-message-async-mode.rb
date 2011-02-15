# edit-message-async-mode
#
module Redwood

class EditMessageAsyncMode < LineCursorMode
  # TODO:
  #
  # * set up keymap - just X to say you're done
  attr_reader :status
  bool_reader :edited

  register_keymap do |k|
    k.add :edit_finished, "Finished editing message", 'E'
  end

  # * initialize function - need
  # ** file path
  # ** info to restart edit mode it started in
  def initialize file_path, title, finish_condition
    @file_path = file_path
    @finish_condition = finish_condition
    @title = title
    
    @text = []
    super {}
  end

  def lines; @text.length end

  def [] i
    @text[i]
  end

protected
  # * override mode bits - killable etc.

  def edit_finished
    # We need a edit_message_async_resume method, but maybe that 
    # should be in another mode?? The below code should run in it
 
    # first make sure any external editor has exited
    File.open(@file_path, 'r') { |f|
      if !f.flock(File::LOCK_EX|File::LOCK_NB)
        # ask user to check that any editor of that file has exited
        # press E again when they are ready
        return false
      end
    }
    # now we resume no matter what
    # first we send the signal to the buffer that killed us
    # then we kill ourselves
    BufferManager.kill_buffer buffer
  end

  # this will be called if <Enter> is pressed
  # nothing useful to do, so make it a no-op until we think of something better
  # to do ...
  def select
    nil
  end
end

end
