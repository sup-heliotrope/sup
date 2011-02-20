require 'thread'

module Redwood

class EditMessageAsyncMode < LineCursorMode

  register_keymap do |k|
    k.add :edit_finished, "Finished editing message", 'E'
#    k.add :path_to_clipboard, "Copy file path to the clipboard", :enter
#    k.add :open_file, "Open file in default GUI editor", 'O'
  end

  def initialize parent_edit_mode, file_path, msg_subject
    @parent_edit_mode = parent_edit_mode
    @file_path = file_path
    @orig_mtime = File.mtime @file_path
    
    @text = ["", "Your message with subject:",  msg_subject, "is saved in a file:", "", @file_path, "", 
             "You can edit your message in the editor of your choice and continue to",
             "use sup while you edit your message.", "",
             "When you have finished editing, select this buffer and press 'E'.",]
    super() 
  end

  def lines; @text.length end

  def [] i
    @text[i]
  end

  def killable?
    !file_being_edited? && !file_has_been_edited?
  end

  def unsaved?
    !file_being_edited? && !file_has_been_edited?
  end

protected

  def edit_finished
    if file_being_edited?
      BufferManager.flash "Please check that #{@file_path} is not open in any editor and try again"
      return false
    end

    debug "Async mode exiting - file is not being edited"
    @parent_edit_mode.edit_message_async_resume
    BufferManager.kill_buffer buffer
    true
  end

  def file_being_edited?
    debug "Checking if file is being edited"
    # check for common editor lock files
    vim_lock_file = File.join(File.dirname(@file_path), '.'+File.basename(@file_path)+'.swp')
    emacs_lock_file = File.join(File.dirname(@file_path), '.#'+File.basename(@file_path))

    return true if File.exist? vim_lock_file
    return true if File.exist? emacs_lock_file

    false
  end

  def file_has_been_edited?
    File.mtime(@file_path) > @orig_mtime
  end

  # to stop select doing anything
  def select
  end
end

end
