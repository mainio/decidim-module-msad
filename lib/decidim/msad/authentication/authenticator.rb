# frozen_string_literal: true

module Decidim
  module Msad
    module Authentication
      class Authenticator
        include ActiveModel::Validations

        def initialize(organization, oauth_hash)
          @organization = organization
          @oauth_hash = oauth_hash
        end

        def verified_email
          @verified_email ||= begin
            if oauth_data[:info][:email]
              oauth_data[:info][:email]
            else
              domain = ::Decidim::Msad.auto_email_domain || organization.host
              "msad-#{person_identifier_digest}@#{domain}"
            end
          end
        end

        def user_params_from_oauth_hash
          return nil if oauth_data.empty?
          return nil if user_identifier.blank?

          {
            provider: oauth_data[:provider],
            uid: user_identifier,
            name: oauth_data[:info][:name],
            # The nickname is automatically "parametrized" by Decidim core from
            # the name string, i.e. it will be in correct format.
            nickname: oauth_data[:info][:nickname] || oauth_data[:info][:name],
            oauth_signature: user_signature,
            avatar_url: oauth_data[:info][:image],
            raw_data: oauth_hash
          }
        end

        def validate!
          raise ValidationError, "No SAML data provided" unless saml_attributes

          actual_attributes = saml_attributes.attributes
          actual_attributes.delete("fingerprint")
          raise ValidationError, "No SAML data provided" if actual_attributes.blank?

          data_blank = actual_attributes.all? { |_k, val| val.blank? }
          raise ValidationError, "Invalid SAML data" if data_blank
          raise ValidationError, "Invalid person dentifier" if person_identifier_digest.blank?

          true
        end

        def identify_user!(user)
          identity = user.identities.find_by(
            organization: organization,
            provider: oauth_data[:provider],
            uid: user_identifier
          )
          return identity if identity

          # Check that the identity is not already bound to another user.
          id = ::Decidim::Identity.find_by(
            organization: organization,
            provider: oauth_data[:provider],
            uid: user_identifier
          )

          raise IdentityBoundToOtherUserError if id

          user.identities.create!(
            organization: organization,
            provider: oauth_data[:provider],
            uid: user_identifier
          )
        end

        def authorize_user!(user)
          authorization = ::Decidim::Authorization.find_by(
            name: "msad_identity",
            unique_id: user_signature
          )
          if authorization
            raise AuthorizationBoundToOtherUserError if authorization.user != user
          else
            authorization = ::Decidim::Authorization.find_or_initialize_by(
              name: "msad_identity",
              user: user
            )
          end

          authorization.attributes = {
            unique_id: user_signature,
            metadata: authorization_metadata
          }
          authorization.save!

          # This will update the "granted_at" timestamp of the authorization
          # which will postpone expiration on re-authorizations in case the
          # authorization is set to expire (by default it will not expire).
          authorization.grant!

          authorization
        end

        # Keeps the user data in sync with the federation server. This is called
        # on every successful login callback request.
        def update_user!(user)
          if user.email != verified_email
            user.email = verified_email
            user.skip_reconfirmation!
            user.save!
          end
        end

        protected

        attr_reader :organization, :oauth_hash

        def oauth_data
          @oauth_data ||= oauth_hash.slice(:provider, :uid, :info)
        end

        def saml_attributes
          @saml_attributes ||= oauth_hash[:extra][:raw_info]
        end

        def user_identifier
          @user_identifier ||= oauth_data[:uid]
        end

        # Create a unique signature for the user that will be used for the
        # granted authorization.
        def user_signature
          @user_signature ||= ::Decidim::OmniauthRegistrationForm.create_signature(
            oauth_data[:provider],
            user_identifier
          )
        end

        def metadata_collector
          @metadata_collector ||= ::Decidim::Msad::Verification::Manager.metadata_collector_for(
            saml_attributes
          )
        end

        # Data that is stored against the authorization "permanently" (i.e. as
        # long as the authorization is valid).
        def authorization_metadata
          metadata_collector.metadata
        end

        # Digested format of the person's identifier to be used in the
        # auto-generated emails. This is used so that the actual identifier is not
        # revealed directly to the end user.
        def person_identifier_digest
          return if user_identifier.blank?

          @person_identifier_digest ||= Digest::MD5.hexdigest(
            "MSAD:#{user_identifier}:#{Rails.application.secrets.secret_key_base}"
          )
        end
      end
    end
  end
end
