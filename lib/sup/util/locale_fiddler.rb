## the following magic enables wide characters when used with a ruby
## ncurses.so that's been compiled against libncursesw. (note the w.) why
## this works, i have no idea. much like pretty much every aspect of
## dealing with curses.  cargo cult programming at its best.
require 'fiddle'
require 'fiddle/import'

module LocaleFiddler
  extend Fiddle::Importer

  SETLOCALE_LIB = case RbConfig::CONFIG['arch']
                  when /darwin/; "libc.dylib"
                  when /cygwin/; "cygwin1.dll"
                  when /freebsd/; "libc.so.7"
                  else; "libc.so.6"
                  end

  dlload SETLOCALE_LIB
  extern "char *setlocale(int, char const *)"

  def setlocale(type, string)
    LocaleFiddler.setlocale(type, string)
  end
end
