# frozen_string_literal: true

require "omniauth"
require "omniauth/strategies/msad"

require_relative "msad/version"
require_relative "msad/engine"
require_relative "msad/authentication"
require_relative "msad/verification"
require_relative "msad/mail_interceptors"

module Decidim
  module Msad
    include ActiveSupport::Configurable

    @configured = false

    # Defines the auto email domain to generate verified email addresses upon
    # the user's registration automatically that have format similar to
    # "msad-identifier@auto-email-domain.fi".
    #
    # In case this is not defined, the default is the organization's domain.
    config_accessor :auto_email_domain

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

    def self.configured?
      @configured
    end

    def self.configure
      @configured = true
      super
    end

    def self.authenticator_for(organization, oauth_hash)
      authenticator_class.new(organization, oauth_hash)
    end

    def self.sp_entity_id
      return config.sp_entity_id if config.sp_entity_id

      "#{application_host}/users/auth/msad/metadata"
    end

    def self.certificate
      return File.read(certificate_file) if certificate_file

      config.certificate
    end

    def self.private_key
      return File.read(private_key_file) if private_key_file

      config.private_key
    end

    def self.omniauth_settings
      {
        idp_metadata_url: idp_metadata_url,
        sp_entity_id: sp_entity_id,
        sp_name_qualifier: sp_entity_id,
        idp_slo_session_destroy: idp_slo_session_destroy,
        sp_metadata: sp_metadata,
        certificate: certificate,
        private_key: private_key,
        # Define the assertion and SLO URLs for the metadata.
        assertion_consumer_service_url: "#{application_host}/users/auth/msad/callback",
        single_logout_service_url: "#{application_host}/users/auth/msad/slo"
      }.merge(extra)
    end

    # Used to determine the default service provider entity ID in case not
    # specifically set by the `sp_entity_id` configuration option.
    def self.application_host
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
