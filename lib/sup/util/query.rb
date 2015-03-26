module Redwood
  module Util
    module Query
      class QueryDescriptionError < ArgumentError; end

      def self.describe(query, fallback = nil)
        d = query.description.force_encoding('UTF-8')

        unless d.valid_encoding?
          raise QueryDescriptionError.new(d) unless fallback
          d = fallback
        end
        d
      end
    end
  end
end
