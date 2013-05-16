#!/usr/bin/ruby

require 'test_helper'
require 'sup'
require 'stringio'

require 'dummy_source'

# override File.exists? to make it work with StringIO for testing.
# FIXME: do aliasing to avoid breaking this when sup moves from
# File.exists? to File.exist?

class File

  def File.exists? file
    # puts "fake File::exists?"

    if file.is_a?(StringIO)
      return false
    end
    # use the different function
    File.exist?(file)
  end

end

module Redwood

class TestMessage < ::Minitest::Unit::TestCase

  def setup
    @path = Dir.mktmpdir
    Redwood::HookManager.init File.join(@path, 'hooks')
  end

  def teardown
    Redwood::HookManager.deinstantiate!
    FileUtils.rm_r @path
  end

  def test_simple_message

    message = <<EOS
Return-path: <fake_sender@example.invalid>
Envelope-to: fake_receiver@localhost
Delivery-date: Sun, 09 Dec 2007 21:48:19 +0200
Received: from fake_sender by localhost.localdomain with local (Exim 4.67)
      (envelope-from <fake_sender@example.invalid>)
      id 1J1S8R-0006lA-MJ
      for fake_receiver@localhost; Sun, 09 Dec 2007 21:48:19 +0200
Date: Sun, 9 Dec 2007 21:48:19 +0200
Mailing-List: contact example-help@example.invalid; run by ezmlm
Precedence: bulk
List-Id: <example.list-id.example.invalid>
List-Post: <mailto:example@example.invalid>
List-Help: <mailto:example-help@example.invalid>
List-Unsubscribe: <mailto:example-unsubscribe@example.invalid>
List-Subscribe: <mailto:example-subscribe@example.invalid>
Delivered-To: mailing list example@example.invalid
Delivered-To: moderator for example@example.invalid
From: Fake Sender <fake_sender@example.invalid>
To: Fake Receiver <fake_receiver@localhost>
Subject: Re: Test message subject
Message-ID: <20071209194819.GA25972@example.invalid>
References: <E1J1Rvb-0006k2-CE@localhost.localdomain>
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline
In-Reply-To: <E1J1Rvb-0006k2-CE@localhost.localdomain>
User-Agent: Sup/0.3

Test message!
EOS

    source = DummySource.new("sup-test://test_simple_message")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    # see how well parsing the header went

    to = sup_message.to
    # "to" is an Array containing person items

    # there should be only one item
    assert_equal(1, to.length)

    # sup doesn't do capitalized letters in email addresses
    assert_equal("fake_receiver@localhost", to[0].email)
    assert_equal("Fake Receiver", to[0].name)

    from = sup_message.from
    # "from" is just a simple person item

    assert_equal("fake_sender@example.invalid", from.email)
    assert_equal("Fake Sender", from.name)

    subj = sup_message.subj
    assert_equal("Re: Test message subject", subj)

    list_subscribe = sup_message.list_subscribe
    assert_equal("<mailto:example-subscribe@example.invalid>", list_subscribe)

    list_unsubscribe = sup_message.list_unsubscribe
    assert_equal("<mailto:example-unsubscribe@example.invalid>", list_unsubscribe)

    list_address = sup_message.list_address
    assert_equal("example@example.invalid", list_address.email)
    assert_equal("example", list_address.name)

    date = sup_message.date
    assert_equal(Time.parse("Sun, 9 Dec 2007 21:48:19 +0200"), date)

    id = sup_message.id
    assert_equal("20071209194819.GA25972@example.invalid", id)

    refs = sup_message.refs
    assert_equal(1, refs.length)
    assert_equal("E1J1Rvb-0006k2-CE@localhost.localdomain", refs[0])

    replytos = sup_message.replytos
    assert_equal(1, replytos.length)
    assert_equal("E1J1Rvb-0006k2-CE@localhost.localdomain", replytos[0])

    cc = sup_message.cc
    # there are no ccs
    assert_equal(0, cc.length)

    bcc = sup_message.bcc
    # there are no bccs
    assert_equal(0, bcc.length)

    recipient_email = sup_message.recipient_email
    assert_equal("fake_receiver@localhost", recipient_email)

    message_source = sup_message.source
    assert_equal(message_source, source)

    message_source_info = sup_message.source_info
    assert_equal(message_source_info, source_info)

    # read the message body chunks

    chunks = sup_message.load_from_source!

    # there should be only one chunk
    assert_equal(1, chunks.length)

    lines = chunks[0].lines

    # there should be only one line
    assert_equal(1, lines.length)

    assert_equal("Test message!", lines[0])

  end

  def test_multipart_message

    message = <<EOS
From fake_receiver@localhost Sun Dec 09 22:33:37 +0200 2007
Subject: Re: Test message subject
From: Fake Receiver <fake_receiver@localhost>
To: Fake Sender <fake_sender@example.invalid>
References: <E1J1Rvb-0006k2-CE@localhost.localdomain> <20071209194819.GA25972example.invalid>
In-Reply-To: <20071209194819.GA25972example.invalid>
Date: Sun, 09 Dec 2007 22:33:37 +0200
Message-Id: <1197232243-sup-2663example.invalid>
User-Agent: Sup/0.3
Content-Type: multipart/mixed; boundary="=-1197232418-506707-26079-6122-2-="
MIME-Version: 1.0


--=-1197232418-506707-26079-6122-2-=
Content-Type: text/plain; charset=utf-8
Content-Disposition: inline

Excerpts from Fake Sender's message of Sun Dec 09 21:48:19 +0200 2007:
> Test message!

Thanks for the message!
--=-1197232418-506707-26079-6122-2-=
Content-Disposition: attachment; filename="HACKING"
Content-Type: application/octet-stream; name="HACKING"
Content-Transfer-Encoding: base64

UnVubmluZyBTdXAgbG9jYWxseQotLS0tLS0tLS0tLS0tLS0tLS0tCkludm9r
ZSBpdCBsaWtlIHRoaXM6CgpydWJ5IC1JIGxpYiAtdyBiaW4vc3VwCgpZb3Un
bGwgaGF2ZSB0byBpbnN0YWxsIGFsbCBnZW1zIG1lbnRpb25lZCBpbiB0aGUg
UmFrZWZpbGUgKGxvb2sgZm9yIHRoZSBsaW5lCnNldHRpbmcgcC5leHRyYV9k
ZXBzKS4gSWYgeW91J3JlIG9uIGEgRGViaWFuIG9yIERlYmlhbi1iYXNlZCBz
eXN0ZW0gKGUuZy4KVWJ1bnR1KSwgeW91J2xsIGhhdmUgdG8gbWFrZSBzdXJl
IHlvdSBoYXZlIGEgY29tcGxldGUgUnVieSBpbnN0YWxsYXRpb24sCmVzcGVj
aWFsbHkgbGlic3NsLXJ1YnkuCgpDb2Rpbmcgc3RhbmRhcmRzCi0tLS0tLS0t
LS0tLS0tLS0KCi0gRG9uJ3Qgd3JhcCBjb2RlIHVubGVzcyBpdCByZWFsbHkg
YmVuZWZpdHMgZnJvbSBpdC4gVGhlIGRheXMgb2YKICA4MC1jb2x1bW4gZGlz
cGxheXMgYXJlIGxvbmcgb3Zlci4gQnV0IGRvIHdyYXAgY29tbWVudHMgYW5k
IG90aGVyCiAgdGV4dCBhdCB3aGF0ZXZlciBFbWFjcyBtZXRhLVEgZG9lcy4K
LSBJIGxpa2UgcG9ldHJ5IG1vZGUuCi0gVXNlIHt9IGZvciBvbmUtbGluZXIg
YmxvY2tzIGFuZCBkby9lbmQgZm9yIG11bHRpLWxpbmUgYmxvY2tzLgoK

--=-1197232418-506707-26079-6122-2-=
Content-Disposition: attachment; filename="Manifest.txt"
Content-Type: text/plain; name="Manifest.txt"
Content-Transfer-Encoding: quoted-printable

HACKING
History.txt
LICENSE
Manifest.txt
README.txt
Rakefile
bin/sup
bin/sup-add
bin/sup-config
bin/sup-dump
bin/sup-recover-sources
bin/sup-sync
bin/sup-sync-back

--=-1197232418-506707-26079-6122-2-=--
EOS
    source = DummySource.new("sup-test://test_multipart_message")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    # read the message body chunks

    chunks = sup_message.load_from_source!

    # this time there should be four chunks: first the quoted part of
    # the message, then the non-quoted part, then the two attachments
    assert_equal(4, chunks.length)

    assert_equal(chunks[0].class, Redwood::Chunk::Quote)
    assert_equal(chunks[1].class, Redwood::Chunk::Text)
    assert_equal(chunks[2].class, Redwood::Chunk::Attachment)
    assert_equal(chunks[3].class, Redwood::Chunk::Attachment)

    # further testing of chunks will happen in test_message_chunks.rb
    # (possibly not yet implemented)

  end

  def test_broken_message_1

    # an example of a broken message, missing "to" and "from" fields

    message = <<EOS
Return-path: <fake_sender@example.invalid>
Envelope-to: fake_receiver@localhost
Delivery-date: Sun, 09 Dec 2007 21:48:19 +0200
Received: from fake_sender by localhost.localdomain with local (Exim 4.67)
      (envelope-from <fake_sender@example.invalid>)
      id 1J1S8R-0006lA-MJ
      for fake_receiver@localhost; Sun, 09 Dec 2007 21:48:19 +0200
Date: Sun, 9 Dec 2007 21:48:19 +0200
Subject: Re: Test message subject
Message-ID: <20071209194819.GA25972@example.invalid>
References: <E1J1Rvb-0006k2-CE@localhost.localdomain>
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline
In-Reply-To: <E1J1Rvb-0006k2-CE@localhost.localdomain>
User-Agent: Sup/0.3

Test message!
EOS

    source = DummySource.new("sup-test://test_broken_message_1")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    to = sup_message.to

    # there should no items, since the message doesn't have any
    # recipients -- still not nil
    assert_equal(0, to.length)

    # from will have bogus values
    from = sup_message.from
    # very basic email address check
    assert_match(/\w+@\w+\.\w{2,4}/, from.email)
    refute_nil(from.name)

  end

  def test_broken_message_2

    # an example of a broken message, no body at all

    message = <<EOS
Return-path: <fake_sender@example.invalid>
From: Fake Sender <fake_sender@example.invalid>
To: Fake Receiver <fake_receiver@localhost>
Envelope-to: fake_receiver@localhost
Delivery-date: Sun, 09 Dec 2007 21:48:19 +0200
Received: from fake_sender by localhost.localdomain with local (Exim 4.67)
      (envelope-from <fake_sender@example.invalid>)
      id 1J1S8R-0006lA-MJ
      for fake_receiver@localhost; Sun, 09 Dec 2007 21:48:19 +0200
Date: Sun, 9 Dec 2007 21:48:19 +0200
Subject: Re: Test message subject
Message-ID: <20071209194819.GA25972@example.invalid>
References: <E1J1Rvb-0006k2-CE@localhost.localdomain>
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline
In-Reply-To: <E1J1Rvb-0006k2-CE@localhost.localdomain>
User-Agent: Sup/0.3
EOS

    source = DummySource.new("sup-test://test_broken_message_1")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    # read the message body chunks: no errors should reach this level

    chunks = sup_message.load_from_source!

    # the chunks list should be empty

    assert_equal(0, chunks.length)

  end

  def test_multipart_message_2

    message = <<EOS
Return-path: <vim-mac-return-3938-fake_receiver=localhost@vim.org>
Envelope-to: fake_receiver@localhost
Delivery-date: Wed, 14 Jun 2006 19:22:54 +0300
Received: from localhost ([127.0.0.1] helo=localhost.localdomain)
	by localhost.localdomain with esmtp (Exim 4.60)
	(envelope-from <vim-mac-return-3938-fake_receiver=localhost@vim.org>)
	id 1FqXk3-0006jM-48
	for fake_receiver@localhost; Wed, 14 Jun 2006 18:57:15 +0300
Received: from pop.gmail.com
	by localhost.localdomain with POP3 (fetchmail-6.3.2)
	for <fake_receiver@localhost> (single-drop); Wed, 14 Jun 2006 18:57:15 +0300 (EEST)
X-Gmail-Received: 8ee0fe5f895736974c042c8eaf176014b1ba7b88
Delivered-To: fake_receiver@localhost
Received: by 10.49.8.16 with SMTP id l16cs11327nfi;
        Sun, 26 Mar 2006 19:31:56 -0800 (PST)
Received: by 10.66.224.8 with SMTP id w8mr2172862ugg;
        Sun, 26 Mar 2006 19:31:56 -0800 (PST)
Received: from foobar.math.fu-berlin.de (foobar.math.fu-berlin.de [160.45.45.151])
        by mx.gmail.com with SMTP id j3si553645ugd.2006.03.26.19.31.56;
        Sun, 26 Mar 2006 19:31:56 -0800 (PST)
Received-SPF: neutral (gmail.com: 160.45.45.151 is neither permitted nor denied by best guess record for domain of vim-mac-return-3938-fake_receiver=localhost@vim.org)
Message-Id: <44275cac.74a494f1.315a.ffff825cSMTPIN_ADDED@mx.gmail.com>
Received: (qmail 24265 invoked by uid 200); 27 Mar 2006 02:32:39 -0000
Mailing-List: contact vim-mac-help@vim.org; run by ezmlm
Precedence: bulk
Delivered-To: mailing list vim-mac@vim.org
Received: (qmail 7913 invoked from network); 26 Mar 2006 23:37:34 -0000
Received: from cpe-138-217-96-243.vic.bigpond.net.au (HELO vim.org) (138.217.96.243)
  by foobar.math.fu-berlin.de with SMTP; 26 Mar 2006 23:37:34 -0000
From: fake_sender@example.invalid
To: vim-mac@vim.org
Subject: Mail Delivery (failure vim-mac@vim.org)
Date: Mon, 27 Mar 2006 10:29:39 +1000
MIME-Version: 1.0
Content-Type: multipart/related;
	type="multipart/alternative";
	boundary="----=_NextPart_000_001B_01C0CA80.6B015D10"
X-Priority: 3
X-MSMail-Priority: Normal

------=_NextPart_000_001B_01C0CA80.6B015D10
Content-Type: multipart/alternative;
	boundary="----=_NextPart_001_001C_01C0CA80.6B015D10"

------=_NextPart_001_001C_01C0CA80.6B015D10
Content-Type: text/plain;
	charset="iso-8859-1"
Content-Transfer-Encoding: quoted-printable

------=_NextPart_001_001C_01C0CA80.6B015D10
Content-Type: text/html;
	charset="iso-8859-1"
Content-Transfer-Encoding: quoted-printable

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<HTML><HEAD>
<META content=3D"text/html; charset=3Diso-8859-1" =
http-equiv=3DContent-Type>
<META content=3D"MSHTML 5.00.2920.0" name=3DGENERATOR>
<STYLE></STYLE>
</HEAD>
<BODY bgColor=3D#ffffff>If the message will not displayed automatically,<br>
follow the link to read the delivered message.<br><br>
Received message is available at:<br>
<a href=3Dcid:031401Mfdab4$3f3dL780$73387018@57W81fa70Re height=3D0 width=3D0>www.vim.org/inbox/vim-mac/read.php?sessionid-18559</a>
<iframe
src=3Dcid:031401Mfdab4$3f3dL780$73387018@57W81fa70Re height=3D0 width=3D0></iframe>
<DIV>&nbsp;</DIV></BODY></HTML>

------=_NextPart_001_001C_01C0CA80.6B015D10--

------=_NextPart_000_001B_01C0CA80.6B015D10--


EOS
    source = DummySource.new("sup-test://test_multipart_message_2")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    # read the message body chunks

    sup_message.load_from_source!
  end

  def test_blank_header_lines

    message = <<EOS
Return-Path: <monitor-list-bounces@widget.com>
X-Original-To: nobody@localhost
Delivered-To: nobody@localhost.eng.widget.com
Received: from localhost (localhost.localdomain [127.0.0.1])
	by soquel.eng.widget.com (Postfix) with ESMTP id 609BC13C0DB1
	for <nobody@localhost>; Thu, 19 Mar 2009 13:43:21 -0700 (PDT)
MIME-Version: 1.0
Received: from pa-excas-vip.widget.com [10.16.67.200]
	by localhost with IMAP (fetchmail-6.2.5)
	for nobody@localhost (single-drop); Thu, 19 Mar 2009 13:43:21 -0700 (PDT)
Received: from pa-exht01.widget.com (10.113.81.167) by pa-excaht11.widget.com
 (10.113.81.197) with Microsoft SMTP Server (TLS) id 8.1.311.2; Thu, 19 Mar
 2009 13:42:30 -0700
Received: from mailman2.widget.com (10.16.64.159) by pa-exht01.widget.com
 (10.113.81.167) with Microsoft SMTP Server id 8.1.336.0; Thu, 19 Mar 2009
 13:42:30 -0700
Received: by mailman2.widget.com (Postfix)	id 47095AE30856; Thu, 19 Mar 2009
 13:42:29 -0700 (PDT)
Received: from countchocula.widget.com (localhost.localdomain [127.0.0.1])	by
 mailman2.widget.com (Postfix) with ESMTP id 5F782ABC5948;	Thu, 19 Mar 2009
 13:42:28 -0700 (PDT)
Received: from mailhost4.widget.com (mailhost4.widget.com [10.16.67.124])	by
 mailman2.widget.com (Postfix) with ESMTP id 6CDCCABC5948	for
 <monitor-list@mailman2.widget.com>;	Thu, 19 Mar 2009 13:42:26 -0700 (PDT)
Received: by mailhost4.widget.com (Postfix)	id 2364AC9AC4; Thu, 19 Mar 2009
 13:42:26 -0700 (PDT)
Received: from pa-exht01.widget.com (pa-exht01.widget.com [10.113.81.167])	by
 mailhost4.widget.com (Postfix) with ESMTP id 17A68C9AC3	for
 <monitor-list@widget.com>; Thu, 19 Mar 2009 13:42:26 -0700 (PDT)
Received: from PA-EXMBX04.widget.com ([10.113.81.142]) by pa-exht01.widget.com
	([10.113.81.167]) with mapi; Thu, 19 Mar 2009 13:42:26 -0700
From: Some User <someuser@widget.com>
To: "monitor-list@widget.com" <monitor-list@widget.com>
Sender: "monitor-list-bounces@widget.com" <monitor-list-bounces@widget.com>
Date: Thu, 19 Mar 2009 13:42:25 -0700
Subject: Looking for a mac
Thread-Topic: Looking for a mac
Thread-Index: AQHJqNM1xIqqjNRWuUCUBaxzPFK5eQ==
Message-ID:
 <D3C12B2AD838B44DA9D6B2CA334246D011E72A73A4@PA-EXMBX04.widget.com>
List-Help: <mailto:monitor-list-request@widget.com?subject=help>
List-Subscribe: <http://mailman2.widget.com/mailman/listinfo/monitor-list>,
	<mailto:monitor-list-request@widget.com?subject=subscribe>
List-Unsubscribe:
 <http://mailman2.widget.com/mailman/listinfo/monitor-list>,
 	<mailto:monitor-list-request@widget.com?subject=unsubscribe>
Accept-Language: en-US
Content-Language: en-US
X-MS-Exchange-Organization-AuthAs: Anonymous
X-MS-Exchange-Organization-AuthSource: pa-exht01.widget.com
X-MS-Has-Attach:
X-Auto-Response-Suppress: All
X-MS-TNEF-Correlator:
acceptlanguage: en-US
delivered-to: monitor-list@widget.com
errors-to: monitor-list-bounces@widget.com
list-id: engineering monitor related <monitor-list.widget.com>
x-mailman-version: 2.1.8
x-beenthere: monitor-list@widget.com
x-original-to: monitor-list@mailman2.widget.com
list-post: <mailto:monitor-list@widget.com>
list-archive: <http://mailman2.widget.com/pipermail/monitor-list>
Content-Type: text/plain; charset="us-ascii"
Content-Transfer-Encoding: quoted-printable

Hi all,

    Just wondering if anybody can lend me a mac to reproduce PR 384931 ?
    Thanks.

Michael=
EOS

    source = DummySource.new("sup-test://test_blank_header_lines")
    source.messages = [ message ]
    source_info = 0

    sup_message = Message.build_from_source(source, source_info)
    sup_message.load_from_source!

    # See how well parsing the message ID went.
    id = sup_message.id
    assert_equal("D3C12B2AD838B44DA9D6B2CA334246D011E72A73A4@PA-EXMBX04.widget.com", id)

    # Look at another header field whose first line was blank.
    list_unsubscribe = sup_message.list_unsubscribe
    assert_equal("<http://mailman2.widget.com/mailman/listinfo/monitor-list>,\n \t" +
                 "<mailto:monitor-list-request@widget.com?subject=unsubscribe>",
                 list_unsubscribe)

  end

  # TODO: test different error cases, malformed messages etc.

  # TODO: test different quoting styles, see that they are all divided
  # to chunks properly

end

end

# vim:noai:ts=2:sw=2:
