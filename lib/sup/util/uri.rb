require "uri"

require "sup/util/path"

module Redwood
  module Util
    module Uri
      def self.build(components)
        components = components.dup
        components[:path] = Path.expand(components[:path])
        ::URI::Generic.build(components)
      end
    end
  end
end
