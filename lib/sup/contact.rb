module Redwood

class ContactManager
  include Singleton

  def initialize fn
    @fn = fn
    @people = {}

    if File.exists? fn
      IO.foreach(fn) do |l|
        l =~ /^(\S+): (.*)$/ or raise "can't parse #{fn} line #{l.inspect}"
        aalias, addr = $1, $2
        @people[aalias] = Person.for addr
      end
    end

    self.class.i_am_the_instance self
  end

  def contacts; @people; end
  def set_contact person, aalias
    oldentry = @people.find { |a, p| p == person }
    @people.delete oldentry.first if oldentry
    @people[aalias] = person
  end
  def drop_contact person; @people.delete person; end
  def delete t; @people.delete t; end
  def resolve aalias; @people[aalias]; end

  def save
    File.open(@fn, "w") do |f|
      @people.keys.sort.each do |aalias|
        f.puts "#{aalias}: #{@people[aalias].full_address}"
      end
    end
  end
end

end
