# frozen_string_literal: true

module Decidim
  module Msad
    class SessionsController < ::Decidim::Devise::SessionsController
      def destroy
        # In case the user is signed in through the AD federation server,
        # redirect them through the SPSLO flow.
        if session.delete("decidim-msad.signed_in")
          # These session variables get destroyed along with the user's active
          # session. They are needed for the SLO request.
          saml_uid = session["saml_uid"]
          saml_session_index = session["saml_session_index"]
          stored_location = stored_location_for(resource_name)

          # End the local user session.
          signed_out = (::Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))

          # Store the SAML parameters for the SLO request utilized by
          # omniauth-saml. These are used to generate a valid SLO request.
          session["saml_uid"] = saml_uid
          session["saml_session_index"] = saml_session_index
          store_location_for(resource_name, stored_location) if stored_location

          # Generate the SLO redirect path and parameters.
          relay = slo_callback_user_session_path
          relay += "?success=1" if signed_out
          params = "?RelayState=#{CGI.escape(relay)}"

          return redirect_to user_msad_omniauth_spslo_path + params
        end

        # Otherwise, continue normally
        super
      end

      def slo
        # This is handled already by omniauth
        redirect_to decidim.root_path
      end

      def spslo
        # This is handled already by omniauth
        redirect_to decidim.root_path
      end

      def slo_callback
        set_flash_message! :notice, :signed_out if params[:success] == "1"

        # Redirect to the root path when the organization forces users to
        # authenticate before accessing the organization.
        return redirect_to(decidim.new_user_session_path) if current_organization.force_users_to_authenticate_before_access_organization

        redirect_to stored_location_for(resource_name) || decidim.root_path
      end
    end
  end
end
