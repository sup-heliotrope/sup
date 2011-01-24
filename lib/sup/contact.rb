module Redwood

class ContactManager
  include Singleton

  def initialize fn
    @fn = fn

    ## maintain the mapping between people and aliases. for contacts without
    ## aliases, there will be no @a2p entry, so @p2a.keys should be treated
    ## as the canonical list of contacts.

    @p2a = {} # person to alias
    @a2p = {} # alias to person
    @e2p = {} # email to person

    if File.exists? fn
      IO.foreach(fn) do |l|
        l =~ /^([^:]*): (.*)$/ or raise "can't parse #{fn} line #{l.inspect}"
        aalias, addr = $1, $2
        update_alias Person.from_address(addr), aalias
      end
    end
  end

  def contacts; @p2a.keys end
  def contacts_with_aliases; @a2p.values.uniq end

  def update_alias person, aalias=nil
    if(old_aalias = @p2a[person]) # remove old alias
      @a2p.delete old_aalias
      @e2p.delete old_aalias.email
    end
    @p2a[person] = aalias
    unless aalias.nil? || aalias.empty?
      @a2p[aalias] = person
      @e2p[person.email] = person
    end
  end

  ## this may not actually be called anywhere, since we still keep contacts
  ## around without aliases to override any fullname changes.
  def drop_contact person
    aalias = @p2a[person]
    @p2a.delete person
    @e2p.delete person.email
    @a2p.delete aalias if aalias
  end

  def contact_for aalias; @a2p[aalias] end
  def alias_for person; @p2a[person] end
  def person_for email; @e2p[email] end
  def is_aliased_contact? person; !@p2a[person].nil? end

  def save
    File.open(@fn, "w") do |f|
      @p2a.sort_by { |(p, a)| [p.full_address, a] }.each do |(p, a)|
        f.puts "#{a || ''}: #{p.full_address}"
      end
    end
  end
end

end
