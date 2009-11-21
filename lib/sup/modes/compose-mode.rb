module Redwood

class ComposeMode < EditMessageMode
  def initialize opts={}
    header = {}
    header["From"] = (opts[:from] || AccountManager.default_account).full_address
    header["To"] = opts[:to].map { |p| p.full_address }.join(", ") if opts[:to]
    header["Cc"] = opts[:cc].map { |p| p.full_address }.join(", ") if opts[:cc]
    header["Bcc"] = opts[:bcc].map { |p| p.full_address }.join(", ") if opts[:bcc]
    header["Subject"] = opts[:subj] if opts[:subj]
    header["References"] = opts[:refs].map { |r| "<#{r}>" }.join(" ") if opts[:refs]
    header["In-Reply-To"] = opts[:replytos].map { |r| "<#{r}>" }.join(" ") if opts[:replytos]

    super :header => header, :body => (opts[:body] || [])
  end

  def edit_message
    edited = super
    BufferManager.kill_buffer self.buffer unless edited
    edited
  end

  def self.spawn_nicely opts={}
    to = opts[:to] || (BufferManager.ask_for_contacts(:people, "To: ", [opts[:to_default]]) or return if ($config[:ask_for_to] != false))
    cc = opts[:cc] || (BufferManager.ask_for_contacts(:people, "Cc: ") or return if $config[:ask_for_cc])
    bcc = opts[:bcc] || (BufferManager.ask_for_contacts(:people, "Bcc: ") or return if $config[:ask_for_bcc])
    subj = opts[:subj] || (BufferManager.ask(:subject, "Subject: ") or return if $config[:ask_for_subject])
    
    mode = ComposeMode.new :from => opts[:from], :to => to, :cc => cc, :bcc => bcc, :subj => subj
    BufferManager.spawn "New Message", mode
    mode.edit_message
  end
end

end
