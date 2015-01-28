module Redwood

class SentManager
  include Redwood::Singleton

  attr_reader :source, :source_uri

  def initialize source_uri
    @source = nil
    @source_uri = source_uri
  end

  def source_id; @source.id; end

  def source= s
    raise FatalSourceError.new("Configured sent_source [#{s.uri}] can't store mail.  Correct your configuration.") unless s.respond_to? :store_message
    @source_uri = s.uri
    @source = s
  end

  def default_source
    @source = SentLoader.new
    @source_uri = @source.uri
    @source
  end

  def write_sent_message date, from_email, &block
    ::Thread.new do
      debug "store the sent message (locking sent source..)"
      @source.synchronize do
        @source.store_message date, from_email, &block
      end
      PollManager.poll_from @source
    end
  end
end

class SentLoader < MBox
  yaml_properties

  def initialize
    @filename = Redwood::SENT_FN
    File.open(@filename, "w") { } unless File.exist? @filename
    super "mbox://" + @filename, true, $config[:archive_sent]
  end

  def file_path; @filename end

  def to_s; 'sup://sent'; end
  def uri; 'sup://sent' end

  def id; 9998; end
  def labels; [:inbox, :sent]; end
  def default_labels; []; end
  def read?; true; end
end

end
