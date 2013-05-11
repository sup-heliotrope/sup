# Sup

A console-based email client with the best features of GMail, mutt and
Emacs.

## Installation

[See the wiki][Installation]

## Features / Problems

Features:

* GMail-like thread-centered archiving, tagging and muting
* [Handling mail from multiple mbox and Maildir sources][sources]
* Blazing fast full-text search with a [rich query language][search]
* Multiple accounts - pick the right one when sending mail
* [Ruby-programmable hooks][hooks]
* Automatically tracking recent contacts

Current limitations which will be fixed:

* [Doesn't run on Ruby 2.0][ruby20]

* Sup doesn't play nicely with other mail clients. Changes in Sup won't be
  synced back to mail source.

* Unix-centrism in MIME attachment handling and in sendmail invocation.

## Problems

Please report bugs to the [Github issue tracker](https://github.com/sup-heliotrope/sup/issues).

## Links

* [Homepage](http://supmua.org/)
* [Code repository](https://github.com/sup-heliotrope/sup)
* [Wiki](https://github.com/sup-heliotrope/sup/wiki)
* IRC: [#sup @ freenode.net](http://webchat.freenode.net/?channels=#sup)
* Mailing list: [sup-talk] and [sup-devel]

## License

```
Copyright (c) 2013       Sup developers.
Copyright (c) 2006--2009 William Morgan.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301, USA.
```

[sources]: https://github.com/sup-heliotrope/sup/wiki/Adding-sources
[hooks]: https://github.com/sup-heliotrope/sup/wiki/Hooks
[search]: https://github.com/sup-heliotrope/sup/wiki/Searching-your-mail
[Installation]: https://github.com/sup-heliotrope/sup/wiki#installation
[ruby20]: https://github.com/sup-heliotrope/sup/wiki/Development#sup-014
[sup-talk]: http://rubyforge.org/mailman/listinfo/sup-talk
[sup-devel]: http://rubyforge.org/mailman/listinfo/sup-devel
