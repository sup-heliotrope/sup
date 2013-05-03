SUP_LIB_DIRS = %w(lib lib/sup lib/sup/modes)
SUP_EXECUTABLES = %w(sup sup-add sup-cmd sup-config sup-dump sup-import-dump sup-recover-sources sup-server sup-sync sup-sync-back sup-tweak-labels sup-psych-ify-config-files)
SUP_EXTRA_FILES = %w(CONTRIBUTORS README.txt LICENSE History.txt ReleaseNotes)
SUP_FILES =
  SUP_EXTRA_FILES +
  SUP_EXECUTABLES.map { |f| "bin/#{f}" } +
  SUP_LIB_DIRS.map { |d| Dir["#{d}/*.rb"] }.flatten

if $0 == __FILE__ # if executed from commandline
  puts SUP_FILES
end
