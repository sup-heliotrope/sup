module Redwood

module CanSpawnComposeMode
  def spawn_compose_mode opts={}
    to = opts[:to] || BufferManager.ask_for_contacts(:people, "To: ") or return
    cc = opts[:cc] || BufferManager.ask_for_contacts(:people, "Cc: ") or return if $config[:ask_for_cc]
    bcc = opts[:bcc] || BufferManager.ask_for_contacts(:people, "Bcc: ") or return if $config[:ask_for_bcc]
    subj = opts[:subj] || BufferManager.ask(:subject, "Subject: ") or return if $config[:ask_for_subject]
    
    mode = ComposeMode.new :from => opts[:from], :to => to, :cc => cc, :bcc => bcc, :subj => subj
    BufferManager.spawn "New Message", mode
    mode.edit_message
  end
end

class ComposeMode < EditMessageMode
  def initialize opts={}
    header = {}
    header["From"] = (opts[:from] || AccountManager.default_account).full_address
    header["To"] = opts[:to].map { |p| p.full_address }.join(", ") if opts[:to]
    header["To"] = opts[:to].map { |p| p.full_address }.join(", ") if opts[:to]
    header["Cc"] = opts[:cc].map { |p| p.full_address }.join(", ") if opts[:cc]
    header["Bcc"] = opts[:bcc].map { |p| p.full_address }.join(", ") if opts[:bcc]
    header["Subject"] = opts[:subj] if opts[:subj]

    super :header => header, :body => (opts[:body] || [])
  end

  def edit_message
    edited = super
    BufferManager.kill_buffer self.buffer unless edited
    edited
  end
end

end
