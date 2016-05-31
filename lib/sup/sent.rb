module Redwood

class SentSource < MBox
  include SerializeLabelsNicely
  yaml_properties :archived, :id, :labels

  def initialize archived=nil, id=nil, labels=nil
    @filename = Redwood::SENT_FN
    File.open(@filename, "w") { } unless File.exist? @filename
    super "mbox://" + @filename, true, archived, id, labels
  end

  def file_path; @filename end

  def to_s; 'sup://sent'; end
  def uri; 'sup://sent' end

  def is_source_for? uri; super || uri == 'sup://sent'; end

  def default_labels; []; end
  def read?; true; end
end

end
