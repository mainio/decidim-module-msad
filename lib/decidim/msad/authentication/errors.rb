# frozen_string_literal: true

module Decidim
  module Msad
    module Authentication
      class Error < StandardError; end

      class AuthorizationBoundToOtherUserError < Error; end
      class IdentityBoundToOtherUserError < Error; end

      class ValidationError < Error
        attr_reader :validation_key

        def initialize(msg = nil, validation_key = :invalid_data)
          @validation_key = validation_key
          super(msg)
        end
      end
    end
  end
end
