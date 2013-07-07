module Redwood
  module Util
    module Query
      def self.describe query
        query.description.force_encoding("UTF-8")
      end
    end
  end
end
