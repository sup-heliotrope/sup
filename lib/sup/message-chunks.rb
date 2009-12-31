require 'tempfile'

## Here we define all the "chunks" that a message is parsed
## into. Chunks are used by ThreadViewMode to render a message. Chunks
## are used for both MIME stuff like attachments, for Sup's parsing of
## the message body into text, quote, and signature regions, and for
## notices like "this message was decrypted" or "this message contains
## a valid signature"---basically, anything we want to differentiate
## at display time.
##
## A chunk can be inlineable, expandable, or viewable. If it's
## inlineable, #color and #lines are called and the output is treated
## as part of the message text. This is how Text and one-line Quotes
## and Signatures work.
##
## If it's not inlineable but is expandable, #patina_color and
## #patina_text are called to generate a "patina" (a one-line widget,
## basically), and the user can press enter to toggle the display of
## the chunk content, which is generated from #color and #lines as
## above. This is how Quote, Signature, and most widgets
## work. Exandable chunks can additionally define #initial_state to be
## :open if they want to start expanded (default is to start collapsed).
##
## If it's not expandable but is viewable, a patina is displayed using
## #patina_color and #patina_text, but no toggling is allowed. Instead,
## if #view! is defined, pressing enter on the widget calls view! and
## (if that returns false) #to_s. Otherwise, enter does nothing. This
##  is how non-inlineable attachments work.
##
## Independent of all that, a chunk can be quotable, in which case it's
## included as quoted text during a reply. Text, Quotes, and mime-parsed
## attachments are quotable; Signatures are not.

## monkey-patch time: make temp files have the right extension
class Tempfile
  def make_tmpname basename, n
    sprintf '%d-%d-%s', $$, n, basename
  end
end


module Redwood
module Chunk
  WRAP_LEN = 80 # wrap messages and text attachments at this width

  class Attachment
    HookManager.register "mime-decode", <<EOS
Decodes a MIME attachment into text form. The text will be displayed
directly in Sup. For attachments that you wish to use a separate program
to view (e.g. images), you should use the mime-view hook instead.

Variables:
   content_type: the content-type of the attachment
        charset: the charset of the attachment, if applicable
       filename: the filename of the attachment as saved to disk
  sibling_types: if this attachment is part of a multipart MIME attachment,
                 an array of content-types for all attachments. Otherwise,
                 the empty array.
Return value:
  The decoded text of the attachment, or nil if not decoded.
EOS

    HookManager.register "mime-view", <<EOS
Views a non-text MIME attachment. This hook allows you to run
third-party programs for attachments that require such a thing (e.g.
images). To instead display a text version of the attachment directly in
Sup, use the mime-decode hook instead.

Note that by default (at least on systems that have a run-mailcap command),
Sup uses the default mailcap handler for the attachment's MIME type. If
you want a particular behavior to be global, you may wish to change your
mailcap instead.

Variables:
   content_type: the content-type of the attachment
       filename: the filename of the attachment as saved to disk
Return value:
  True if the viewing was successful, false otherwise. If false, calling
  /usr/bin/run-mailcap will be tried.
EOS
#' stupid ruby-mode

    ## raw_content is the post-MIME-decode content. this is used for
    ## saving the attachment to disk.
    attr_reader :content_type, :filename, :lines, :raw_content
    bool_reader :quotable

    def initialize content_type, filename, encoded_content, sibling_types
      @content_type = content_type.downcase
      @filename = filename
      @quotable = false # changed to true if we can parse it through the
                        # mime-decode hook, or if it's plain text
      @raw_content =
        if encoded_content.body
          encoded_content.decode
        else
          "For some bizarre reason, RubyMail was unable to parse this attachment.\n"
        end

      text = case @content_type
      when /^text\/plain\b/
        Iconv.easy_decode $encoding, encoded_content.charset || $encoding, @raw_content
      else
        HookManager.run "mime-decode", :content_type => content_type,
                        :filename => lambda { write_to_disk },
                        :charset => encoded_content.charset,
                        :sibling_types => sibling_types
      end

      @lines = nil
      if text
        @lines = text.gsub("\r\n", "\n").gsub(/\t/, "        ").gsub(/\r/, "").split("\n")
        @lines = lines.map {|l| l.chomp.wrap WRAP_LEN}.flatten
        @quotable = true
      end
    end

    def color; :none end
    def patina_color; :attachment_color end
    def patina_text
      if expandable?
        "Attachment: #{filename} (#{lines.length} lines)"
      else
        "Attachment: #{filename} (#{content_type}; #{@raw_content.size.to_human_size})"
      end
    end

    ## an attachment is exapndable if we've managed to decode it into
    ## something we can display inline. otherwise, it's viewable.
    def inlineable?; false end
    def expandable?; !viewable? end
    def initial_state; :open end
    def viewable?; @lines.nil? end
    def view_default! path
      case Config::CONFIG['arch']
        when /darwin/
          cmd = "open '#{path}'"
        else
          cmd = "/usr/bin/run-mailcap --action=view '#{@content_type}:#{path}'"
      end
      debug "running: #{cmd.inspect}"
      BufferManager.shell_out(cmd)
      $? == 0
    end

    def view!
      path = write_to_disk
      ret = HookManager.run "mime-view", :content_type => @content_type,
                                         :filename => path
      ret || view_default!(path)
    end

    def write_to_disk
      file = Tempfile.new(@filename || "sup-attachment")
      file.print @raw_content
      file.close
      file.path
    end

    ## used when viewing the attachment as text
    def to_s
      @lines || @raw_content
    end
  end

  class Text

    attr_reader :lines
    def initialize lines
      @lines = lines.map { |l| l.chomp.wrap WRAP_LEN }.flatten # wrap

      ## trim off all empty lines except one
      @lines.pop while @lines.length > 1 && @lines[-1] =~ /^\s*$/ && @lines[-2] =~ /^\s*$/
    end

    def inlineable?; true end
    def quotable?; true end
    def expandable?; false end
    def viewable?; false end
    def color; :none end
  end

  class Quote
    attr_reader :lines
    def initialize lines
      @lines = lines
    end
    
    def inlineable?; @lines.length == 1 end
    def quotable?; true end
    def expandable?; !inlineable? end
    def viewable?; false end

    def patina_color; :quote_patina_color end
    def patina_text; "(#{lines.length} quoted lines)" end
    def color; :quote_color end
  end

  class Signature
    attr_reader :lines
    def initialize lines
      @lines = lines
    end

    def inlineable?; @lines.length == 1 end
    def quotable?; false end
    def expandable?; !inlineable? end
    def viewable?; false end

    def patina_color; :sig_patina_color end
    def patina_text; "(#{lines.length}-line signature)" end
    def color; :sig_color end
  end

  class EnclosedMessage
    attr_reader :lines
    def initialize from, to, cc, date, subj
      @from = from ? "unknown sender" : from.full_adress
      @to = to ? "" : to.map { |p| p.full_address }.join(", ")
      @cc = cc ? "" : cc.map { |p| p.full_address }.join(", ")
      if date
        @date = date.rfc822
      else
        @date = ""
      end

      @subj = subj

      @lines = "\nFrom: #{from}\n"
      @lines += "To: #{to}\n"
      if !cc.empty?
        @lines += "Cc: #{cc}\n"
      end
      @lines += "Date: #{date}\n"
      @lines += "Subject: #{subj}\n\n"
    end

    def inlineable?; false end
    def quotable?; false end
    def expandable?; true end
    def initial_state; :closed end
    def viewable?; false end

    def patina_color; :generic_notice_patina_color end
    def patina_text; "Begin enclosed message sent on #{@date}" end

    def color; :quote_color end
  end

  class CryptoNotice
    attr_reader :lines, :status, :patina_text

    def initialize status, description, lines=[]
      @status = status
      @patina_text = description
      @lines = lines
    end

    def patina_color
      case status
      when :valid then :cryptosig_valid_color
      when :invalid then :cryptosig_invalid_color
      else :cryptosig_unknown_color
      end
    end
    def color; patina_color end

    def inlineable?; false end
    def quotable?; false end
    def expandable?; !@lines.empty? end
    def viewable?; false end
  end
end
end
