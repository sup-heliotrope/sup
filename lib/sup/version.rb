def git_suffix
  revision = `GIT_DIR=#{__dir__}/../../.git git rev-parse HEAD 2>/dev/null`
  if revision.empty?
    "-git-unknown"
  else
    "-git-#{revision[0..7]}"
  end
end

module Redwood
  VERSION = "1.2#{git_suffix}"
end
