module Redwood

class EditMessageAsyncMode < LineCursorMode

  HookManager.register "async-edit", <<EOS
Runs when 'H' is pressed in async edit mode. You can run whatever code
you want here - though the default case would be launching a text
editor. Your hook is assumed to not block, so you should use exec() or
fork() to launch the editor.

Once the hook has returned then sup will be responsive as usual. You will
still need to press 'E' to exit this buffer and send the message.

Variables:
file_path: The full path to the file containing the message to be edited.

Return value: None
EOS

  register_keymap do |k|
    k.add :run_async_hook, "Run the async-edit hook", 'H'
    k.add :edit_finished, "Finished editing message", 'E'
    k.add :path_to_clipboard, "Copy file path to the clipboard", :enter
  end

  def initialize parent_edit_mode, file_path, msg_subject
    @parent_edit_mode = parent_edit_mode
    @file_path = file_path
    @orig_mtime = File.mtime @file_path

    @text = ["ASYNC MESSAGE EDIT",
             "", "Your message with subject:",  msg_subject, "is saved in a file:", "", @file_path, "", 
             "You can edit your message in the editor of your choice and continue to",
             "use sup while you edit your message.", "",
             "Press <Enter> to have the file path copied to the clipboard.", "",
             "When you have finished editing, select this buffer and press 'E'.",]
    super()
  end

  def lines; @text.length end

  def [] i
    @text[i]
  end

  def killable?
    if file_being_edited?
      if !BufferManager.ask_yes_or_no("It appears the file is still being edited. Are you sure?")
        return false
      end
    end

    @parent_edit_mode.edit_message_async_resume true
    true
  end

  def unsaved?
    !file_being_edited? && !file_has_been_edited?
  end

protected

  def edit_finished
    if file_being_edited?
      if !BufferManager.ask_yes_or_no("It appears the file is still being edited. Are you sure?")
        return false
      end
    end

    @parent_edit_mode.edit_message_async_resume
    BufferManager.kill_buffer buffer
    true
  end

  def path_to_clipboard
    if system("which xsel > /dev/null 2>&1")
      # linux/unix path
      IO.popen('xsel --clipboard --input', 'r+') { |clipboard| clipboard.puts(@file_path) }
      BufferManager.flash "Copied file path to clipboard."
    elsif system("which pbcopy > /dev/null 2>&1")
      # mac path
      IO.popen('pbcopy', 'r+') { |clipboard| clipboard.puts(@file_path) }
      BufferManager.flash "Copied file path to clipboard."
    else
      BufferManager.flash "No way to copy text to clipboard - try installing xsel."
    end
  end

  def run_async_hook
    HookManager.run("async-edit", {:file_path => @file_path})
  end

  def file_being_edited?
    # check for common editor lock files
    vim_lock_file = File.join(File.dirname(@file_path), '.'+File.basename(@file_path)+'.swp')
    emacs_lock_file = File.join(File.dirname(@file_path), '.#'+File.basename(@file_path))

    return true if File.exist?(vim_lock_file) || File.exist?(emacs_lock_file)

    false
  end

  def file_has_been_edited?
    File.mtime(@file_path) > @orig_mtime
  end

end

end
