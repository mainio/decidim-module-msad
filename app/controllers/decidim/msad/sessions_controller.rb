# frozen_string_literal: true

module Decidim
  module Msad
    class SessionsController < ::Decidim::Devise::SessionsController
      def destroy
        # Unless the user is signed in through the AD federation server,
        # continue normally.
        return super unless session.delete("decidim-msad.signed_in")

        # If the user is signed in through AD federation server, redirect them
        # through the SPSLO flow if it is enabled.
        tenant_name = session.delete("decidim-msad.tenant")
        tenant = Decidim::Msad.tenants.find { |t| t.name == tenant_name }
        raise "Unkown MSAD tenant: #{tenant_name}" unless tenant

        # If SPSLO is disabled, continue normally.
        return super if tenant.disable_spslo

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

        # Individual sign out path for each tenant to pass it to correct
        # OmniAuth handler.
        sign_out_path = send("user_#{tenant.name}_omniauth_spslo_path")

        redirect_to sign_out_path + params
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
