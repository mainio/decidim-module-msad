# frozen_string_literal: true

module Decidim
  module Msad
    class OmniauthCallbacksController < ::Decidim::Devise::OmniauthRegistrationsController
      # Make the view helpers available needed in the views
      helper Decidim::Msad::Engine.routes.url_helpers
      helper_method :omniauth_registrations_path

      skip_before_action :verify_authenticity_token, only: [:msad, :failure]
      skip_after_action :verify_same_origin_request, only: [:msad, :failure]

      # This is called always after the user returns from the authentication
      # flow from the Active Directory identity provider.
      def msad
        session["decidim-msad.signed_in"] = true
        session["decidim-msad.tenant"] = tenant.name

        authenticator.validate!

        if user_signed_in?
          # The user is most likely returning from an authorization request
          # because they are already signed in. In this case, add the
          # authorization and redirect the user back to the authorizations view.

          # Make sure the user has an identity created in order to aid future
          # Active Directory sign ins. In case this fails, it will raise a
          # Decidim::Msad::Authentication::IdentityBoundToOtherUserError
          # which is handled below.
          authenticator.identify_user!(current_user)

          # Add the authorization for the user
          return fail_authorize unless authorize_user(current_user)

          # Make sure the user details are up to date
          authenticator.update_user!(current_user)

          # Show the success message and redirect back to the authorizations
          flash[:notice] = t(
            "authorizations.create.success",
            scope: "decidim.msad.verification"
          )
          return redirect_to(
            stored_location_for(resource || :user) ||
            decidim.root_path
          )
        end

        # Normal authentication request, proceed with Decidim's internal logic.
        send(:create)
      rescue Decidim::Msad::Authentication::ValidationError => e
        fail_authorize(e.validation_key)
      rescue Decidim::Msad::Authentication::IdentityBoundToOtherUserError
        fail_authorize(:identity_bound_to_other_user)
      end

      def failure
        strategy = failed_strategy
        saml_response = strategy.response_object if strategy
        return super unless saml_response

        # In case we want more info about the returned status codes, use the
        # code below.
        #
        # Status codes:
        #   Requester = A problem with the request OR the user cancelled the
        #               request at the identity provider.
        #   Responder = The handling of the request failed.
        #   VersionMismatch = Wrong version in the request.
        #
        # Additional state codes:
        #   AuthnFailed = The authentication failed OR the user cancelled
        #                 the process at the identity provider.
        #   RequestDenied = The authenticating endpoint (which the
        #                   identity provider redirects to) rejected the
        #                   authentication.
        # if !saml_response.send(:validate_success_status) && !saml_response.status_code.nil?
        #   codes = saml_response.status_code.split(" | ").map do |full_code|
        #     full_code.split(":").last
        #   end
        # end

        # Some extra validation checks
        validations = [
          # The success status validation fails in case the response status
          # code is something else than "Success". This is most likely because
          # of one the reasons explained above. In general there are few
          # possible explanations for this:
          # 1. The user cancelled the request and returned to the service.
          # 2. The underlying identity service the IdP redirects to rejected
          #    the request for one reason or another. E.g. the user cancelled
          #    the request at the identity service.
          # 3. There is some technical problem with the identity provider
          #    service or the XML request sent to there is malformed.
          :success_status,
          # Checks if the local session should be expired, i.e. if the user
          # took too long time to go through the authorization endpoint.
          :session_expiration,
          # The NotBefore and NotOnOrAfter conditions failed, i.e. whether the
          # request is handled within the allowed timeframe by the IdP.
          :conditions
        ]
        validations.each do |key|
          next if saml_response.send("validate_#{key}")

          flash[:alert] = t(".#{key}")
          return redirect_to after_omniauth_failure_path_for(resource_name)
        end

        super
      end

      # This is overridden method from the Devise controller helpers
      # This is called when the user is successfully authenticated which means
      # that we also need to add the authorization for the user automatically
      # because a succesful Active Directory authentication means the user has
      # been successfully authorized as well.
      def sign_in_and_redirect(resource_or_scope, *args)
        # Add authorization for the user
        if resource_or_scope.is_a?(::Decidim::User)
          return fail_authorize unless authorize_user(resource_or_scope)

          # Make sure the user details are up to date
          authenticator.update_user!(resource_or_scope)
        end

        super
      end

      # Disable authorization redirect for the first login
      def first_login_and_not_authorized?(_user)
        false
      end

      private

      def authorize_user(user)
        authenticator.authorize_user!(user)
      rescue Decidim::Msad::Authentication::AuthorizationBoundToOtherUserError
        nil
      end

      def fail_authorize(failure_message_key = :already_authorized)
        flash[:alert] = t(
          "failure.#{failure_message_key}",
          scope: "decidim.#{tenant.name}.omniauth_callbacks"
        )

        redirect_path = stored_location_for(resource || :user) || decidim.root_path
        if session.delete("decidim-msad.signed_in")
          tenant = session.delete("decidim-msad.tenant")
          params = "?RelayState=#{CGI.escape(redirect_path)}"
          sign_out_path = send("user_#{tenant}_omniauth_spslo_path")

          return redirect_to sign_out_path + params
        end

        redirect_to redirect_path
      end

      # Needs to be specifically defined because the core engine routes are not
      # all properly loaded for the view and this helper method is needed for
      # defining the omniauth registration form's submit path.
      def omniauth_registrations_path(resource)
        Decidim::Core::Engine.routes.url_helpers.omniauth_registrations_path(resource)
      end

      # Private: Create form params from omniauth hash
      # Since we are using trusted omniauth data we are generating a valid signature.
      def user_params_from_oauth_hash
        authenticator.user_params_from_oauth_hash
      end

      def authenticator
        @authenticator ||= tenant.authenticator_for(
          current_organization,
          oauth_hash
        )
      end

      def tenant
        @tenant ||= begin
          matches = request.path.match(%r{^/users/auth/([^/]+)/.+})
          raise "Invalid MSAD tenant" unless matches

          name = matches[1]
          tenant = Decidim::Msad.tenants.find { |t| t.name == name }
          raise "Unkown MSAD tenant: #{name}" unless tenant

          tenant
        end
      end

      def verified_email
        authenticator.verified_email
      end
    end
  end
end
