module Redwood

class SearchManager
  include Singleton

  class ExpansionError < StandardError; end

  def initialize fn
    @fn = fn
    @searches = {}
    if File.exists? fn
      IO.foreach(fn) do |l|
        l =~ /^([^:]*): (.*)$/ or raise "can't parse #{fn} line #{l.inspect}"
        @searches[$1] = $2
      end
    end
    @modified = false
  end

  def all_searches; return @searches.keys.sort; end
  def search_string_for name; return @searches[name]; end
  def valid_name? name; name =~ /^[\w-]+$/; end
  def name_format_hint; "letters, numbers, underscores and dashes only"; end

  def add name, search_string
    return unless valid_name? name
    @searches[name] = search_string
    @modified = true
  end

  def rename old, new
    return unless @searches.has_key? old
    search_string = @searches[old]
    delete old if add new, search_string
  end

  def edit name, search_string
    return unless @searches.has_key? name
    @searches[name] = search_string
    @modified = true
  end

  def delete name
    return unless @searches.has_key? name
    @searches.delete name
    @modified = true
  end

  def expand search_string
    expanded = search_string.dup
    until (matches = expanded.scan(/\{([\w-]+)\}/).flatten).empty?
      if !(unknown = matches - @searches.keys).empty?
        error_message = "Unknown \"#{unknown.join('", "')}\" when expanding \"#{search_string}\""
      elsif expanded.size >= 2048
        error_message = "Check for infinite recursion in \"#{search_string}\""
      end
      if error_message
        warn error_message
        raise ExpansionError, error_message
      end
      matches.each { |n| expanded.gsub! "{#{n}}", "(#{@searches[n]})" if @searches.has_key? n }
    end
    return expanded
  end

  def save
    return unless @modified
    File.open(@fn, "w") { |f| @searches.sort.each { |(n, s)| f.puts "#{n}: #{s}" } }
    @modified = false
  end
end

end
