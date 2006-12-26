sup
    by William Morgan <wmorgan-sup@masanjin.net>
    http://sup.rubyforge.org

== DESCRIPTION:

Sup is a console-based email client that combines the best
features of GMail, mutt, and emacs. Sup matches the power of GMail
with the speed and simplicity of a console interface.

Sup makes it easy to:
- Handle massive amounts of email.

- Mix email from different sources: mbox files (even across
  different machines), IMAP folders, POP accounts, and GMail
  accounts.

- Instantaneously search over your entire email collection. Search
  over body text, or use a query language to combine search
  predicates in any way.

- Handle multiple accounts. Replying to email sent to a particular
  account will use the correct SMTP server, signature, and from
  address.

- Add custom code to handle certain types of messages or to handle
  certain types of text within messages.

- Organize email with user-defined labels, automatically track
  recent contacts, and much more!

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

- Labels instead of folders. Drop that tired old metaphor and you'll
  see how much easier it is to organize email.

- GMail-style thread management.  Archive a thread, and it will
  disappear from your inbox until someone replies. Kill a thread, and
  it will never come back to your inbox. (But it will still show up in
  searches, of course.)

- Console based interface. No mouse clicking required!

- Programmability. It's in Ruby. The code is good. It's easy to
  extend.

- Multiple buffer support. Why be limited to viewing one thread at a
  time?

- Tons of other little features, like automatic context-sensitive
  help, multi-message operations, MIME attachment viewing, recent
  contact list generation, etc.

Current limitations which will be fixed:

- Support for mbox and IMAP only at this point. No support for POP, mh,
  or GMail mailstores.

- No internationalization support. No wide characters, no subject
  demangling. 

- Unix-centrism in MIME attachment handling and in sendmail
  invocation.

- Several obvious missing features, like undo, filters / saved
  searches, message annotations, etc.

== SYNOPSYS:

  1. sup-import <source>+
  2. sup
  3. edit ~/.sup/config.yaml for the (very few) settings sup has

  Where <source> is a filename (for mbox files), or an imap or imaps
  url. In the case of imap, don't put the username and password in
  the URI (which is a terrible, terrible idea). You will be prompted
  for them.

  sup-import has several options which control whether you want
  messages from particular mailboxes not to be added to the inbox,
  or not to be marked as new, so run it with -h for help.

  Note that Sup never changes the contents of any mailboxes; it only
  indexes in to them. So it shouldn't ever corrupt your mail. The flip
  side is that if you change a mailbox (e.g. delete messages, or, in
  the case of mbox files, read an unread message) then Sup may crash,
  and will tell you to run sup-import --rebuild to recalculate the
  offsets within the mailbox.

== REQUIREMENTS:

* ferret >= 0.10.13
* ncurses >= 0.9.1
* rmail >= 0.17

== INSTALL:

* gem install sup -y
* Then, in rmail, change line 159 of multipart.rb to:
    chunk = chunk[0..start]
  (Sorry; it's an unsupported package.) You might be able to get away
  without doing this but if you get frozen string exceptions when
  reading in multipart messages, this is what you need to change.

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

