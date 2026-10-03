Authentication-Results: mail-a.sr.ht; dkim=none 
Received: from smtp02.aussiebb.com.au (unknown [121.200.0.93])
	by mail-a.sr.ht (Postfix) with ESMTPS id C7D921FFE2
	for <~sircmpwn/public-inbox@lists.sr.ht>; Sat, 11 Apr 2026 09:26:03 +0000 (UTC)
Received: from localhost (localhost.localdomain [127.0.0.1])
	by smtp02.aussiebb.com.au (Postfix) with ESMTP id 3E06E101B25
	for <~sircmpwn/public-inbox@lists.sr.ht>; Sat, 11 Apr 2026 19:25:55 +1000 (AEST)
X-Virus-Scanned: Debian amavis at smtp02.aussiebb.com.au
Received: from smtp02.aussiebb.com.au ([127.0.0.1])
 by localhost (smtp02.aussiebb.com.au [127.0.0.1]) (amavis, port 10024)
 with ESMTP id DMHmZ0WHyx_y for <~sircmpwn/public-inbox@lists.sr.ht>;
 Sat, 11 Apr 2026 19:25:55 +1000 (AEST)
Received: by smtp02.aussiebb.com.au (Postfix, from userid 116)
	id 2676A101CFB; Sat, 11 Apr 2026 19:25:55 +1000 (AEST)
X-Spam-Checker-Version: SpamAssassin 4.0.0 (2022-12-13) on
	smtp02.aussiebb.com.au
X-Spam-Level: *
X-Spam-Status: No, score=2.0 required=10.0 tests=DMARC_PASS,FORGED_SPF_HELO,
	KHOP_HELO_FCRDNS,SPF_HELO_PASS,URIBL_BLOCKED autolearn=disabled
	version=4.0.0
Received: from djc.id.au (honeycomb.djc.id.au [IPv6:2403:5818:89c3::35])
	(using TLSv1.3 with cipher TLS_AES_256_GCM_SHA384 (256/256 bits)
	 key-exchange X25519 server-signature RSA-PSS (2048 bits) server-digest SHA256)
	(No client certificate requested)
	by smtp02.aussiebb.com.au (Postfix) with ESMTPS id 2B9AF101B25
	for <~sircmpwn/public-inbox@lists.sr.ht>; Sat, 11 Apr 2026 19:25:54 +1000 (AEST)
Received: by djc.id.au (Postfix, from userid 1000)
	id 9B20A3550383; Sat, 11 Apr 2026 19:25:53 +1000 (AEST)
From: Dan Callaghan <djc@djc.id.au>
To: ~sircmpwn/public-inbox@lists.sr.ht
Cc: Dan Callaghan <djc@djc.id.au>
Subject: [PATCH] add Sup to the list of plain text certified mail clients
Date: Sat, 11 Apr 2026 19:25:25 +1000
Message-ID: <20260411092525.498926-1-djc@djc.id.au>
X-Mailer: git-send-email 2.51.2
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit

Sup is a mature TUI mail client, originally released in 2008 and still
actively maintained. It favours displaying text/plain parts, and
outgoing mails are composed in plain text. It uses traditional reply
quoting style and encourages bottom posting.
---
 es/index.html | 3 +++
 index.html    | 3 +++
 2 files changed, 6 insertions(+)

diff --git a/es/index.html b/es/index.html
index 7697315..f42aee3 100644
--- a/es/index.html
+++ b/es/index.html
@@ -118,6 +118,9 @@ <h2 id="recommended-clients"><a href="#recommended-clients">
       <li>
         <a rel="noopener" href="https://www.squirrelmail.org/">SquirrelMail</a> (Web)
       </li>
+      <li>
+        <a rel="noopener" href="https://supmua.dev/">Sup</a> (TUI)
+      </li>
       <li>
         <a rel="noopener" href="https://github.com/wanderlust/wanderlust">Wanderlust</a> (emacs)
       </li>
diff --git a/index.html b/index.html
index e38cb60..3244b16 100644
--- a/index.html
+++ b/index.html
@@ -121,6 +121,9 @@ <h2 id="recommended-clients"><a href="#recommended-clients">
       <li>
         <a rel="noopener" href="https://www.squirrelmail.org/">SquirrelMail</a> (Webmail)
       </li>
+      <li>
+        <a rel="noopener" href="https://supmua.dev/">Sup</a> (TUI)
+      </li>
       <li>
         <a rel="noopener" href="https://github.com/wanderlust/wanderlust">Wanderlust</a> (emacs)
       </li>
-- 
2.51.2

