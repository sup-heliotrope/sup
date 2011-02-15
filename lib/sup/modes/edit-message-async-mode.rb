require 'thread'

module Redwood

class EditMessageAsyncMode < LineCursorMode

  register_keymap do |k|
    k.add :edit_finished, "Finished editing message", 'E'
  end

  def initialize parent_edit_mode, file_path
    @parent_edit_mode = parent_edit_mode
    @file_path = file_path
    
    @text = ["Your message is saved in a file:", "", @file_path, "", 
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
    !file_being_edited?
  end

  def unsaved?
    !file_being_edited?
  end

protected

  def edit_finished
    if file_being_edited?
      BufferManager.flash "Please check that #{@file_path} is not open in any editor and try again"
      return false
    end

    @parent_edit_mode.edit_message_async_resume
    BufferManager.kill_buffer buffer
  end

  def file_being_edited?
    begin
      File.open(@file_path, 'r') { |f|
        return true if !f.flock(File::LOCK_EX|File::LOCK_NB)
      }
    rescue
      return true
    end
    false
  end

  # nothing useful to do, so make it a no-op until we think of something better
  def select
    nil
  end
end

end
