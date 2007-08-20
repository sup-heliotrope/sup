module Redwood

class ComposeMode < EditMessageMode
  def initialize opts={}
    header = {
      "From" => AccountManager.default_account.full_address,
    }

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
