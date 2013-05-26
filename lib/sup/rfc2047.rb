## from: http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-talk/101949

# $Id: rfc2047.rb,v 1.4 2003/04/18 20:55:56 sam Exp $
# MODIFIED slightly by William Morgan
#
# An implementation of RFC 2047 decoding.
#
# This module depends on the iconv library by Nobuyoshi Nakada, which I've
# heard may be distributed as a standard part of Ruby 1.8. Many thanks to him
# for helping with building and using iconv.
#
# Thanks to "Josef 'Jupp' Schugt" <jupp / gmx.de> for pointing out an error with
# stateful character sets.
#
# Copyright (c) Sam Roberts <sroberts / uniserve.com> 2004
#
# This file is distributed under the same terms as Ruby.

module Rfc2047
  WORD = %r{=\?([!\#$%&'*+-/0-9A-Z\\^\`a-z{|}~]+)\?([BbQq])\?([!->@-~]+)\?=} # :nodoc: 'stupid ruby-mode
  WORDSEQ = %r{(#{WORD.source})\s+(?=#{WORD.source})}

  def Rfc2047.is_encoded? s; s =~ WORD end

  # Decodes a string, +from+, containing RFC 2047 encoded words into a target
  # character set, +target+. See iconv_open(3) for information on the
  # supported target encodings. If one of the encoded words cannot be
  # converted to the target encoding, it is left in its encoded form.
  def Rfc2047.decode_to(target, from)
    from = from.gsub(WORDSEQ, '\1')
    out = from.gsub(WORD) do
      |word|
      charset, encoding, text = $1, $2, $3

      # B64 or QP decode, as necessary:
      case encoding
        when 'b', 'B'
          #puts text
          text = text.unpack('m*')[0]
          #puts text.dump

        when 'q', 'Q'
          # RFC 2047 has a variant of quoted printable where a ' ' character
          # can be represented as an '_', rather than =32, so convert
          # any of these that we find before doing the QP decoding.
          text = text.tr("_", " ")
          text = text.unpack('M*')[0]

        # Don't need an else, because no other values can be matched in a
        # WORD.
      end

      text.transcode(target, charset)
    end
  end
end
