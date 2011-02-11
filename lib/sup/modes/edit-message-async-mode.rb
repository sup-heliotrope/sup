# edit-message-async-mode
#

class EditMessageAsyncMode < Mode
  # TODO:
  #
  # * set up keymap - just X to say you're done

  # * generate buffer text
  # * override mode bits - killable etc.

  # * initialize function - need
  # ** file path
  # ** info to restart edit mode it started in
  def initialize
  end

  def edit_finished
    #
    # We need a edit_message_async_resume method, but maybe that 
    # should be in another mode?? The below code should run in it
 
    # first make sure any external editor has exited
    File.open(@file.path, 'r') { |f|
      while !f.flock(File::LOCK_EX|File::LOCK_NB)
        # ask user to check that any editor of that file has exited
        # press enter when ready to continue
      end
    }
    @edited = true if File.mtime(@file.path) > @mtime

    return @edited unless @edited

    header, @body = parse_file @file.path
    @header = header - NON_EDITABLE_HEADERS
    handle_new_text @header, @body
    update

    @edited
  end
end
