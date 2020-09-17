# frozen_string_literal: true

require "omniauth-saml"
require "omniauth/msad/metadata"
require "omniauth/msad/settings"

module OmniAuth
  module Strategies
    class MSAD < SAML
      # The IdP metadata URL.
      option :idp_metadata_url, nil

      # These are the requested attributes that could be defined for the
      # metadata. However, these can be already defined at the federation side,
      # so they are not generally needed with AD based federations.
      option :request_attributes, []

      # Maps the SAML attributes to OmniAuth info schema:
      # https://github.com/omniauth/omniauth/wiki/Auth-Hash-Schema#schema-10-and-later
      option(
        :attribute_statements,
        name: %w(http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name),
        email: %w(http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress),
        first_name: %w(http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname),
        last_name: %w(http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname),
        nickname: %w(http://schemas.microsoft.com/identity/claims/displayname)
      )

      option(:sp_metadata, [])

      info do
        found_attributes = options.attribute_statements.map do |key, values|
          attribute = find_attribute_by(values)
          [key, attribute]
        end
        info_hash = Hash[found_attributes]

        # The name attribute is overridden if the first name and last name are
        # defined because otherwise it could be the principal name which is not
        # a user readable name as expected by OmniAuth.
        name = "#{info_hash["first_name"]} #{info_hash["last_name"]}".strip
        info_hash["name"] = name unless name.blank?

        info_hash
      end

      def initialize(app, *args, &block)
        super

        # Add the request attributes to the options.
        options[:sp_name_qualifier] = options[:sp_entity_id] if options[:sp_name_qualifier].nil?

        # Remove the nil options from the origianl options array that will be
        # defined by the MSAD options
        [
          :idp_name_qualifier,
          :name_identifier_format,
          :security
        ].each do |key|
          options.delete(key) if options[key].nil?
        end

        # Add the MSAD options to the local options, most of which are fetched
        # from the metadata. The options array is the one that gets priority in
        # case it overrides some of the metadata or locally defined option
        # values.
        @options = OmniAuth::Strategy::Options.new(
          msad_options.merge(options)
        )
      end

      # This method can be used externally to fetch information about the
      # response, e.g. in case of failures.
      def response_object
        return nil unless request.params["SAMLResponse"]

        with_settings do |settings|
          response = OneLogin::RubySaml::Response.new(
            request.params["SAMLResponse"],
            options_for_response_object.merge(settings: settings)
          )
          response.attributes["fingerprint"] = settings.idp_cert_fingerprint
          response
        end
      end

      private

      def msad_options
        idp_metadata_parser = OneLogin::RubySaml::IdpMetadataParser.new

        # Returns OneLogin::RubySaml::Settings prepopulated with idp metadata
        settings = begin
          begin
            idp_metadata_parser.parse_remote_to_hash(
              options.idp_metadata_url,
              true
            )
          rescue ::URI::InvalidURIError
            # Allow the OmniAuth strategy to be configured with empty settings
            # in order to provide the metadata URL even when the authentication
            # endpoint is not configured.
            {}
          end
        end

        # Define the security settings as there are some defaults that need to be
        # modified
        security_defaults = OneLogin::RubySaml::Settings::DEFAULTS[:security]
        settings[:security] = security_defaults.merge(
          authn_requests_signed: options.certificate.present?,
          want_assertions_signed: true,
          digest_method: XMLSecurity::Document::SHA256,
          signature_method: XMLSecurity::Document::RSA_SHA256
        )

        # Add some extra information that is necessary for correctly formatted
        # logout requests.
        settings[:idp_name_qualifier] = settings[:idp_entity_id]

        # If the name identifier format is not defined in the IdP metadata, add
        # the persistent format to the SP metadata.
        settings[:name_identifier_format] ||= "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"

        settings
      end

      def with_settings
        options[:assertion_consumer_service_url] ||= callback_url
        yield OmniAuth::MSAD::Settings.new(options)
      end

      # Customize the metadata class in order to add custom nodes to the
      # metadata.
      def other_phase_for_metadata
        with_settings do |settings|
          response = OmniAuth::MSAD::Metadata.new

          add_request_attributes_to(settings) if options.request_attributes.length.positive?

          Rack::Response.new(
            response.generate(settings),
            200,
            "Content-Type" => "application/xml"
          ).finish
        end
      end

      # End the local user session BEFORE sending the logout request to the
      # identity provider.
      def other_phase_for_spslo
        return super unless options.idp_slo_target_url

        with_settings do |settings|
          # Some session variables are needed when generating the logout request
          request = generate_logout_request(settings)
          # Destroy the local user session
          options[:idp_slo_session_destroy].call @env, session
          # Send the logout request to the identity provider
          redirect(request)
        end
      end

      # Overridden to disable passing the relay state with a request parameter
      # which is possible in the default implementation.
      def slo_relay_state
        state = super

        # Ensure that we are only using the relay states to redirect the user
        # within the current website. This forces the relay state to always
        # start with a single forward slash character (/).
        return "/" unless state =~ %r{^/[^/].*}

        state
      end
    end
  end
end

OmniAuth.config.add_camelization "msad", "MSAD"
