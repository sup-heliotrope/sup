module Redwood

class SentManager
  include Singleton

  attr_reader :source, :source_uri

  def initialize source_uri
    @source = nil
    @source_uri = source_uri
  end

  def source_id; @source.id; end

  def source= s
    raise FatalSourceError.new("Configured sent_source [#{s.uri}] can't store mail.  Correct your configuration.") unless s.respond_to? :store_message
    @souce_uri = s.uri
    @source = s
  end

  def default_source
    @source = Recoverable.new SentLoader.new
    @source_uri = @source.uri
    @source
  end

  def write_sent_message date, from_email, &block
    @source.store_message date, from_email, &block

    PollManager.each_message_from(@source) do |m|
      m.remove_label :unread
      m.add_label :sent
      PollManager.add_new_message m
    end
  end
end

class SentLoader < MBox::Loader
  yaml_properties

  def initialize
    @filename = Redwood::SENT_FN
    File.open(@filename, "w") { } unless File.exists? @filename
    super "mbox://" + @filename, true, true
  end

  def file_path; @filename end

  def to_s; 'sup://sent'; end
  def uri; 'sup://sent' end

  def id; 9998; end
  def labels; [:inbox, :sent]; end
end

end
