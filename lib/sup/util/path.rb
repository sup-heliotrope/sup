module Redwood
  module Util
    module Path
      def self.expand(path)
        ::File.expand_path(path)
      end
    end
  end
end
