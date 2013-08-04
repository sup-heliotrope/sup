module Redwood
  module Util
    module Query
      class QueryDescriptionError < ArgumentError; end

      def self.describe query
        d = query.description.force_encoding("UTF-8")

        raise QueryDescriptionError.new(d) unless d.valid_encoding?
        return d
      end
    end
  end
end
