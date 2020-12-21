# frozen_string_literal: true

module Decidim
  module Msad
    class Tenant
      include ActiveSupport::Configurable

      # Individual name for the tenant. Not relevant if you only configure a
      # single tenant, the default name "msad" is sufficient in that case. If
      # you have multiple tenants, use an individual name for each tenant, e.g.
      # "ad_internal" and "ad_external".
      #
      # The name can only contain lowercase characters and underscores.
      config_accessor :name, instance_writer: false do
        "msad"
      end

      # Defines the auto email domain to generate verified email addresses upon
      # the user's registration automatically that have format similar to
      # "msad-identifier@auto-email-domain.fi".
      #
      # In case this is not defined, the default is the organization's domain.
      config_accessor :auto_email_domain

      config_accessor :idp_metadata_file
      config_accessor :idp_metadata_url
      config_accessor :sp_entity_id, instance_reader: false

      # The certificate string for the application
      config_accessor :certificate, instance_reader: false

      # The private key string for the application
      config_accessor :private_key, instance_reader: false

      # The certificate file for the application
      config_accessor :certificate_file

      # The private key file for the application
      config_accessor :private_key_file

      # The SLO requests to ADFS need to be signed in order for them to work
      # properly. For ADFS, the sign out requests need to be signed which
      # requires a certificate and private key to be defined for the tenant.
      # If you are using ADFS and cannot configure a certificate and private
      # key, you can disable the SP initiated sign out requests (SPSLO) by
      # setting this configuration to `true`.
      config_accessor :disable_spslo do
        false
      end

      # Defines how the session gets cleared when the OmniAuth strategy logs the
      # user out. This has been customized to preserve the flash messages and the
      # stored redirect location in the session after the session is destroyed.
      config_accessor :idp_slo_session_destroy do
        proc do |_env, session|
          flash = session["flash"]
          return_to = session["user_return_to"]
          result = session.clear
          session["flash"] = flash if flash
          session["user_return_to"] = return_to if return_to
          result
        end
      end

      # These are extra attributes that can be stored for the authorization
      # metadata. Define these as follows:
      #
      # Decidim::Msad.configure do |config|
      #   # ...
      #   config.metadata_attributes = {
      #     primary_group_sid: "http://schemas.microsoft.com/ws/2008/06/identity/claims/primarygroupsid",
      #     groups: { name: "http://schemas.xmlsoap.org/claims/Group", type: :multi }
      #   }
      # end
      config_accessor :metadata_attributes do
        {}
      end

      # Extra metadata to be included in the service provider metadata. Define as
      # follows:
      #
      # Decidim::Msad.configure do |config|
      #   # ...
      #   config.sp_metadata = [
      #     {
      #       name: "Organization",
      #       children: [
      #         {
      #           name: "OrganizationName",
      #           attributes: { "xml:lang" => "en-US" },
      #           content: "Acme"
      #         }
      #       ]
      #     }
      #   ]
      # end
      config_accessor :sp_metadata do
        []
      end

      # Extra configuration for the omniauth strategy
      config_accessor :extra do
        {}
      end

      # Defines whether registered users are automatically subscribed to the
      # newsletters during the OmniAuth registration flow. This is only updated
      # during the first login, so users can still unsubscribe if they later
      # decide they don't want to receive the newsletter and later logins will not
      # change the subscription state.
      config_accessor :registration_newsletter_subscriptions do
        false
      end

      # Allows customizing the authorization workflow e.g. for adding custom
      # workflow options or configuring an action authorizer for the
      # particular needs.
      config_accessor :workflow_configurator do
        lambda do |workflow|
          # By default, expiration is set to 0 minutes which means it will
          # never expire.
          workflow.expires_in = 0.minutes
        end
      end

      # Allows customizing parts of the authentication flow such as validating
      # the authorization data before allowing the user to be authenticated.
      config_accessor :authenticator_class do
        Decidim::Msad::Authentication::Authenticator
      end

      # Allows customizing how the authorization metadata gets collected from
      # the SAML attributes passed from the authorization endpoint.
      config_accessor :metadata_collector_class do
        Decidim::Msad::Verification::MetadataCollector
      end

      def initialize
        yield self
      end

      def name=(name)
        unless name =~ /^[a-z_]+$/
          raise(
            InvalidTenantName,
            "The MSAD tenant name can only contain lowercase letters and underscores."
          )
        end
        config.name = name
      end

      def authenticator_for(organization, oauth_hash)
        authenticator_class.new(self, organization, oauth_hash)
      end

      def metadata_collector_for(saml_attributes)
        metadata_collector_class.new(self, saml_attributes)
      end

      def sp_entity_id
        return config.sp_entity_id if config.sp_entity_id

        "#{application_host}/users/auth/#{config.name}/metadata"
      end

      def certificate
        return File.read(certificate_file) if certificate_file

        config.certificate
      end

      def private_key
        return File.read(private_key_file) if private_key_file

        config.private_key
      end

      def omniauth_settings
        {
          name: name,
          strategy_class: OmniAuth::Strategies::MSAD,
          idp_metadata_file: idp_metadata_file,
          idp_metadata_url: idp_metadata_url,
          sp_entity_id: sp_entity_id,
          sp_name_qualifier: sp_entity_id,
          idp_slo_session_destroy: idp_slo_session_destroy,
          sp_metadata: sp_metadata,
          certificate: certificate,
          private_key: private_key,
          # Define the assertion and SLO URLs for the metadata.
          assertion_consumer_service_url: "#{application_host}/users/auth/#{config.name}/callback",
          single_logout_service_url: "#{application_host}/users/auth/#{config.name}/slo"
        }.merge(extra)
      end

      def setup!
        setup_routes!

        # Configure the SAML OmniAuth strategy for Devise
        ::Devise.setup do |config|
          config.omniauth(name.to_sym, omniauth_settings)
        end

        # Customized version of Devise's OmniAuth failure app in order to handle
        # the failures properly. Without this, the failure requests would end
        # up in an ActionController::InvalidAuthenticityToken exception.
        devise_failure_app = OmniAuth.config.on_failure
        OmniAuth.config.on_failure = proc do |env|
          if env["PATH_INFO"] =~ %r{^/users/auth/#{config.name}($|/.+)}
            env["devise.mapping"] = ::Devise.mappings[:user]
            Decidim::Msad::OmniauthCallbacksController.action(
              :failure
            ).call(env)
          else
            # Call the default for others.
            devise_failure_app.call(env)
          end
        end
      end

      def setup_routes!
        # This assignment makes the config variable accessible in the block
        # below.
        config = self.config
        Decidim::Msad::Engine.routes do
          devise_scope :user do
            # Manually map the SAML omniauth routes for Devise because the default
            # routes are mounted by core Decidim. This is because we want to map
            # these routes to the local callbacks controller instead of the
            # Decidim core.
            # See: https://git.io/fjDz1
            match(
              "/users/auth/#{config.name}",
              to: "omniauth_callbacks#passthru",
              as: "user_#{config.name}_omniauth_authorize",
              via: [:get, :post]
            )

            match(
              "/users/auth/#{config.name}/callback",
              to: "omniauth_callbacks#msad",
              as: "user_#{config.name}_omniauth_callback",
              via: [:get, :post]
            )

            # Add the SLO and SPSLO paths to be able to pass these requests to
            # OmniAuth.
            match(
              "/users/auth/#{config.name}/slo",
              to: "sessions#slo",
              as: "user_#{config.name}_omniauth_slo",
              via: [:get, :post]
            )

            match(
              "/users/auth/#{config.name}/spslo",
              to: "sessions#spslo",
              as: "user_#{config.name}_omniauth_spslo",
              via: [:get, :post]
            )
          end
        end
      end

      def auto_email_for(organization, identifier_digest)
        domain = auto_email_domain || organization.host
        "#{name}-#{identifier_digest}@#{domain}"
      end

      def auto_email_matches?(email)
        return false unless auto_email_domain

        email =~ /^#{name}-[a-z0-9]{32}@#{auto_email_domain}$/
      end

      # Used to determine the default service provider entity ID in case not
      # specifically set by the `sp_entity_id` configuration option.
      def application_host
        conf = Rails.application.config
        url_options = conf.action_controller.default_url_options
        url_options = conf.action_mailer.default_url_options if !url_options || !url_options[:host]
        url_options ||= {}

        # Note that at least Azure AD requires all callback URLs to be HTTPS, so
        # we'll default to that.
        host = url_options[:host]
        port = url_options[:port]
        protocol = url_options[:protocol]
        protocol = port.to_i == 80 ? "http" : "https" if protocol.blank?
        if host.blank?
          # Default to local development environment.
          host = "localhost"
          port ||= 3000
        end

        return "#{protocol}://#{host}:#{port}" if port && ![80, 443].include?(port.to_i)

        "#{protocol}://#{host}"
      end
    end
  end
end
