module Redwood

class ContactManager
  include Singleton

  def initialize fn
    @fn = fn
    @p2a = {} # person to alias map
    @a2p = {} # alias to person map

    if File.exists? fn
      IO.foreach(fn) do |l|
        l =~ /^([^:]+): (.*)$/ or raise "can't parse #{fn} line #{l.inspect}"
        aalias, addr = $1, $2
        p = PersonManager.person_for addr, :definitive => true
        @p2a[p] = aalias
        @a2p[aalias] = p
      end
    end

    self.class.i_am_the_instance self
  end

  def contacts; @p2a.keys; end
  def set_contact person, aalias
    if(pold = @a2p[aalias]) && (pold != person)
      drop_contact pold
    end
    @p2a[person] = aalias
    @a2p[aalias] = person
  end
  def drop_contact person
    if(aalias = @p2a[person])
      @p2a.delete person
      @a2p.delete aalias
    end
  end    
  def contact_for aalias; @a2p[aalias]; end
  def alias_for person; @p2a[person]; end
  def is_contact? person; @p2a.member? person; end

  def save
    File.open(@fn, "w") do |f|
      @p2a.each do |p, a|
        f.puts "#{a}: #{p.full_address}"
      end
    end
  end
end

end
