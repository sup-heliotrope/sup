require 'sup'

puts "loading index..."
@index = Redwood::Index.new
@index.load
@i = @index.index
puts "loaded index of #{@i.size} messages"


