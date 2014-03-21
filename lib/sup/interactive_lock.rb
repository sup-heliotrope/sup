require 'fileutils'

module Redwood

## wrap a nice interactive layer on top of anything that has a #lock method
## which throws a LockError which responds to #user, #host, #mtim, #pname, and
## #pid.

module InteractiveLock
  def pluralize number_of, kind; "#{number_of} #{kind}" + (number_of == 1 ? "" : "s") end

  def time_ago_in_words time
    secs = (Time.now - time).to_i
    mins = secs / 60
    time = if mins == 0
      pluralize secs, "second"
    else
      pluralize mins, "minute"
    end
  end

  DELAY = 5 # seconds

  def lock_interactively stream=$stderr
    begin
      Index.lock
    rescue Index::LockError => e
      begin
        Process.kill 0, e.pid.to_i # 0 signal test the existence of PID
        stream.puts <<EOS
  Error: the index is locked by another process! User '#{e.user}' on
  host '#{e.host}' is running #{e.pname} with pid #{e.pid}.
  The process was alive as of at least #{time_ago_in_words e.mtime} ago.

EOS
        stream.print "Should I ask that process to kill itself (y/n)? "
        stream.flush
        if $stdin.gets =~ /^\s*y(es)?\s*$/i
          Process.kill "TERM", e.pid.to_i
          sleep DELAY
          stream.puts "Let's try that again."
          begin
            Index.lock
          rescue Index::LockError => e
            stream.puts "I couldn't lock the index. The lockfile might just be stale."
            stream.print "Should I just remove it and continue? (y/n) "
            stream.flush
            if $stdin.gets =~ /^\s*y(es)?\s*$/i
              begin
                FileUtils.rm e.path
              rescue Errno::ENOENT
                stream.puts "The lockfile doesn't exists. We continue."
              end
              stream.puts "Let's try that one more time."
              begin
                Index.lock
              rescue Index::LockError => e
                stream.puts "I couldn't unlock the index."
                return false
              end
              return true
            end
          end
        end
      rescue Errno::ESRCH # no such process
        stream.puts "I couldn't lock the index. The lockfile might just be stale."
        begin
          FileUtils.rm e.path
        rescue Errno::ENOENT
          stream.puts "The lockfile doesn't exists. We continue."
        end
        stream.puts "Let's try that one more time."
        begin
          sleep DELAY
          Index.lock
        rescue Index::LockError => e
          stream.puts "I couldn't unlock the index."
          return false
        end
        return true
      end
      stream.puts "Sorry, couldn't unlock the index."
      return false
    end
    return true
  end
end

end
