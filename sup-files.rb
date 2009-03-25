SUP_LIB_DIRS = %w(lib lib/sup lib/sup/modes lib/sup/mbox)
SUP_EXECUTABLES = %w(sup sup-add sup-config sup-dump sup-recover-sources sup-sync sup-sync-back sup-tweak-labels)
SUP_EXTRA_FILES = %w(CONTRIBUTORS README.txt LICENSE History.txt ReleaseNotes)
SUP_FILES =
  SUP_EXTRA_FILES +
  SUP_EXECUTABLES.map { |f| "bin/#{f}" } +
  SUP_LIB_DIRS.map { |d| Dir["#{d}/*.rb"] }.flatten
