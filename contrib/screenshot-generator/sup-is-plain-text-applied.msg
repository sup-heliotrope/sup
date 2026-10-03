Authentication-Results: mail-a.sr.ht; dkim=pass header.d=ddevault.org header.i=@ddevault.org
Received: from mx.freebitcoin.gay (mx.freebitcoin.gay [92.65.121.143])
	by mail-a.sr.ht (Postfix) with ESMTPS id 13F73200E0
	for <~sircmpwn/public-inbox@lists.sr.ht>; Mon, 20 Apr 2026 07:26:50 +0000 (UTC)
DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=ddevault.org;
	s=_bikeshed; t=1776670002;
	h=from:from:reply-to:subject:subject:date:date:message-id:message-id:
	 to:to:cc:mime-version:mime-version:content-type:content-type:
	 in-reply-to:in-reply-to:references:references;
	bh=/yTIwruVpbRgzboJc+lUtE3TsCGqQmxSUE8vJiuBYB0=;
	b=TfqhiwTaygLnt3sbmZNT1qMNIcaPYGPyTMRJpNOsfALmwG5g91xf1RVO8BpnSB4D45LZMP
	h26PRpF2bBW8oRYRfaSsMwiSl0T2ucPlH08rIWPNBuq4roZAvPH+Ga6RKp9RcNhSsMMvwh
	2h9/1KDKFNUA2P/kdRjlifSjaCsnmKc=
Received: from taiga (mx.freebitcoin.gay [92.65.121.143])
	by mail.freebitcoin.gay (OpenSMTPD) with ESMTPSA id 7314ef4d (TLSv1.3:TLS_AES_256_GCM_SHA384:256:NO);
	Mon, 20 Apr 2026 09:26:42 +0200 (CEST)
Received: by taiga (Postfix, from userid 1000)
	id 9EFA3BA002F; Mon, 20 Apr 2026 09:26:49 +0200 (CEST)
Mime-Version: 1.0
Content-Type: multipart/signed;
 boundary=a036da96ce29d60f01d793f8b11ad804cb7659b0e414c63118649b669cdc;
 micalg=pgp-sha512; protocol="application/pgp-signature"
Date: Mon, 20 Apr 2026 09:26:49 +0200
Message-Id: <DHXSYEQU1SFY.1W0NFHNML13VB@ddevault.org>
From: "Drew DeVault" <drew@ddevault.org>
To: "Dan Callaghan" <djc@djc.id.au>, <~sircmpwn/public-inbox@lists.sr.ht>
Subject: Re: [PATCH] add Sup to the list of plain text certified mail
 clients
X-Sourcehut-Patchset-Update: APPLIED
References: <20260411092525.498926-1-djc@djc.id.au>
In-Reply-To: <20260411092525.498926-1-djc@djc.id.au>

--a036da96ce29d60f01d793f8b11ad804cb7659b0e414c63118649b669cdc
Content-Type: multipart/mixed;
 boundary=1d16b06c6066296315555c6776a0e1d688a41caf8c9cea66a5cdcdcfd42a

--1d16b06c6066296315555c6776a0e1d688a41caf8c9cea66a5cdcdcfd42a
Content-Type: multipart/alternative;
 boundary=a95442b43616d7ee1f8d1e2ae129e5a85862edd92378eb2f25ff009758ef

--a95442b43616d7ee1f8d1e2ae129e5a85862edd92378eb2f25ff009758ef
Content-Transfer-Encoding: quoted-printable
Content-Disposition: inline
Content-Type: text/plain; charset=UTF-8

Thanks!

To git@git.sr.ht:~sircmpwn/useplaintext.email
   e22de97..70ed7d5  master -> master

--a95442b43616d7ee1f8d1e2ae129e5a85862edd92378eb2f25ff009758ef--

--1d16b06c6066296315555c6776a0e1d688a41caf8c9cea66a5cdcdcfd42a
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename=42F3F1862E3CC4B8.asc
Content-Type: application/pgp-keys; charset=UTF-8

LS0tLS1CRUdJTiBQR1AgUFVCTElDIEtFWSBCTE9DSy0tLS0tCgptRE1FWjdZOWt4WUpLd1lCQkFI
YVJ3OEJBUWRBL3BQeTZYK25OTDVUMlFhSktFTTA4eE4vS3o3d0ZUQVpvSDVZCnJpVjl4MW0wSUVS
eVpYY2dSR1ZXWVhWc2RDQThaSEpsZDBCa1pHVjJZWFZzZEM1dmNtYytpSk1FRXhZS0FEc0MKR3dN
RkN3a0lCd0lDSWdJR0ZRb0pDQXNDQkJZQ0F3RUNIZ2NDRjRBV0lRU2Z0ZWMzM0NXeW5ZN3NScEZD
OC9HRwpManpFdUFVQ1o3WTl3d0FLQ1JCQzgvR0dManpFdU1FRUFQOURIKzFMZ3ZUcVpETFo4YmFi
QjVDZHA1eTBaVytRClR4NzhtaDFMOGpKZDZnRUFzc21nc0ltY3JadjRhZFAyVVc1UlU1QkhDZTlL
VWR4MER5VjgzUXdsRkFTNE9BUm4KdGoyVEVnb3JCZ0VFQVpkVkFRVUJBUWRBR0FIOWRsYUNPTm9Y
cG1RZ0hvUWdZSTJ0UytWTTNtelU4STJQeVZZUQoxR1VEQVFnSGlIZ0VHQllLQUNBQ0d3d1dJUVNm
dGVjMzNDV3luWTdzUnBGQzgvR0dManpFdUFVQ1o3WTkxZ0FLCkNSQkM4L0dHTGp6RXVIY25BUDR5
ak9pTTB5cWtTVDZ5WHpEVVd6ZTdCOUltMjRGOEhWeCt3TnFjRGFEdGNBRC8KZktRaHowU0NQaWJs
TzZsYzdNRlV2bGFPejJ2ODdVcFVZUmh6UGRnUXF3az0KPWVtcmIKLS0tLS1FTkQgUEdQIFBVQkxJ
QyBLRVkgQkxPQ0stLS0tLQo=
--1d16b06c6066296315555c6776a0e1d688a41caf8c9cea66a5cdcdcfd42a--

--a036da96ce29d60f01d793f8b11ad804cb7659b0e414c63118649b669cdc
Content-Type: application/pgp-signature; name="signature.asc"

-----BEGIN PGP SIGNATURE-----

iHUEABYKAB0WIQSftec33CWynY7sRpFC8/GGLjzEuAUCaeXVOQAKCRBC8/GGLjzE
uJRIAPwOx55M404obNqpVNWkeipGH68mQlprxiQqztCT6jG5qgD+LUPSDChxMpmo
ogLdO5Rb3UDRet4xWy0fjSAxT34AHgA=
=tPvL
-----END PGP SIGNATURE-----

--a036da96ce29d60f01d793f8b11ad804cb7659b0e414c63118649b669cdc--
