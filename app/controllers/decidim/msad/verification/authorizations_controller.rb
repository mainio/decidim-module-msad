# frozen_string_literal: true

module Decidim
  module Msad
    module Verification
      class AuthorizationsController < ::Decidim::ApplicationController
        skip_before_action :store_current_location

        def new
          # Do not enforce the permission here because it would cause
          # re-authorizations not to work as the authorization already exists.
          # In case the user wants to re-authorize themselves, they can just
          # hit this endpoint again.
          # The redirection happens in the view as it needs to be a POST
          # request.
        end
      end
    end
  end
end
