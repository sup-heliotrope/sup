sup
    by William Morgan <wmorgan-sup@masanjin.net>
    http://sup.rubyforge.org

== DESCRIPTION:

Sup is an attempt to take the UI innovations of web-based email
readers (ok, really just GMail) and to combine them with the
traditional wholesome goodness of a console-based email client.

Sup is designed to work with massive amounts of email, potentially
spread out across different mbox files, IMAP folders, and GMail
accounts, and to pull them all together into a single interface.

The goal of Sup is to become the email client of choice for nerds
everywhere.

== FEATURES/PROBLEMS:

Features:

- Scalability to massive amounts of email. Immediate startup and
  operability, regardless of how much amount of email you have.
  (At least, once everything's been indexed.)

- Immediate full-text search of your entire email archive, using
  the full Ferret query langauge. Search over message bodies, labels,
  from: and to: fields, or any combination thereof.

- Thread-centrism. Operations are performed at the thread, not the
  message level. Entire threads are manipulated and viewed (with
  redundancies removed) at a time.

- Labels over folders. Drop that tired old metaphor and you'll see how
  much easier it is to organize email.

- GMail-style thread management.  Archive a thread, and it will
  disappear from your inbox until someone replies. Kill a thread, and
  it will never come back to your inbox. (But it will still show up in
  searches, of course.)

- Console based, so instantaneous response to interaction. No mouse
  clicking required!

- Programmability. It's in Ruby. The code is good. It's easy to
  extend.

- Multiple buffer support. Why be limited to viewing one thread at a
  time?

- Automatic context-sensitive help.

- Message tagging and multi-message tagged operations.

- Mutt-style MIME attachment viewing.

Current limitations which will be fixed:

- Support for mbox ONLY at this point. No support for POP, IMAP, and
  GMail accounts.

- No internationalization support. No wide characters, no subject
  demangling. 

- No GMail-style filters.

- Unix-centrism in MIME attachment handling.

== SYNOPSYS:

  1. sup-import <mbox filename>+
  2. sup
  3. edit ~/.sup/config.yaml for the (very few) settings sup has

  sup-import has several options which control whether you want
  messages from particular mailboxes not to be added to the inbox,
  or not to be marked as new, so run it with -h for help.

  Note that Sup *never* changes the contents of any mailboxes. So it
  shouldn't ever corrupt your mail. The flip side is that if you
  change a mailbox (e.g. delete or read messages) then Sup may crash,
  and will tell you to run sup-import --rebuild to recalculate the
  offsets within the mailbox have changed.

== REQUIREMENTS:

* ferret >= 0.10.13
* ncurses >= 0.9.1
* rmail >= 0.17

== INSTALL:

* gem install sup -y
* Then, in rmail, change line 159 of multipart.rb to:
    chunk = chunk[0..start]
  (Sorry. it's an unsupported package.) You might be able to get away
  without doing this but if you get frozen string exceptions when
  reading in multipart email messages, this is what you need to
  change.

== LICENSE:

Copyright (c) 2006 William Morgan.

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

