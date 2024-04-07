# Sup

Sup is a console-based email client for people with a lot of email.

<img src="https://sup-heliotrope.github.io/images/old_screenshot_1.png" />

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

Current limitations:

* Sup does in general not play nicely with other mail clients, not all
  changes can be synced back to the mail source. Refer to [Maildir Syncback][maildir-syncback]
  in the wiki for this recently included feature. Maildir Syncback
  allows you to sync back flag changes in messages and to write messages
  to maildir sources.

* Unix-centrism in MIME attachment handling and in sendmail invocation.

## Problems

Please report bugs to the [GitHub issue tracker](https://github.com/sup-heliotrope/sup/issues).

## Links

* [Homepage](https://sup-heliotrope.github.io/)
* [Code repository](https://github.com/sup-heliotrope/sup)
* [Wiki](https://github.com/sup-heliotrope/sup/wiki)
* Mailing list: supmua@googlegroups.com (subscribe: supmua+subscribe@googlegroups.com, archive: https://groups.google.com/d/forum/supmua )

## Maintenance status

Sup is a mature, production-quality mail client. The maintainers are also
long-term users, and mainly focus on preserving the current feature set. Pull
requests are very welcome, especially to fix bugs or improve compatibility,
however pull requests for major new features are unlikely to be merged.

## Alternatives

If Sup is missing a feature you are interested in, it might be possible to
accomplish using Sup's [powerful hooks mechanism][hooks]. Otherwise, here are
some alternatives to consider:

* [Notmuch](https://notmuchmail.org/) was inspired by Sup. There are a wide
  variety of [Notmuch clients](https://notmuchmail.org/frontends/) available.
  The most similar to Sup's look-and-feel is
  [Alot](https://github.com/pazz/alot) &mdash; also a curses-based front end.
  Alot even ships with a
  [built-in](https://github.com/pazz/alot/blob/master/extra/themes/sup)
  [Sup theme](https://github.com/pazz/alot/wiki/Gallery#user-content-theme-sup)!

* [mu](https://www.djcbsoftware.nl/code/mu/) /
  [mu4e](https://www.djcbsoftware.nl/code/mu/mu4e.html). Like Sup, a search-based
  email back end, and also implemented using Xapian. The emacs-based front end
  [is quite different](https://www.djcbsoftware.nl/code/mu/mu4e/Other-mail-clients.html).

## License

```
Copyright (c) 2013--     Sup developers.
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
[maildir-syncback]: https://github.com/sup-heliotrope/sup/wiki/Using-sup-with-other-clients
