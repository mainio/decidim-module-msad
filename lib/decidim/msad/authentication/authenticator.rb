# frozen_string_literal: true

module Decidim
  module Msad
    module Authentication
      class Authenticator
        include ActiveModel::Validations

        def initialize(tenant, organization, oauth_hash)
          @tenant = tenant
          @organization = organization
          @oauth_hash = oauth_hash
          @new_user = false
        end

        def verified_email
          @verified_email ||= begin
            if oauth_data[:info][:email]
              oauth_data[:info][:email]
            else
              tenant.auto_email_for(organization, person_identifier_digest)
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

        # Validate gets run very early in the authentication flow as it's the
        # first method to call before anything else is done. The purpose of this
        # method is to check that the authentication data returned by the AD
        # federation service is valid and contains all the information that we
        # would expect. Therefore, it "validates" that the authentication can
        # be performed.
        def validate!
          raise ValidationError, "No SAML data provided" unless saml_attributes

          actual_attributes = saml_attributes.attributes
          actual_attributes.delete("fingerprint")
          raise ValidationError, "No SAML data provided" if actual_attributes.blank?

          data_blank = actual_attributes.all? { |_k, val| val.blank? }
          raise ValidationError, "Invalid SAML data" if data_blank
          raise ValidationError, "Invalid person dentifier" if person_identifier_digest.blank?

          # Check if there is already an existing identity which is bound to an
          # existing user record. If the identity is not found or the user
          # record bound to that identity no longer exists, the signed in user
          # is a new user.
          id = ::Decidim::Identity.find_by(
            organization: organization,
            provider: oauth_data[:provider],
            uid: user_identifier
          )
          @new_user = id ? id.user.blank? : true

          true
        end

        # User is only identified in case they were already logged in during the
        # authentication flow. This can happen in case the service allows public
        # registrations and authorization through MSAD is enabled in the user's
        # profile. This adds a new identity to an existing user unless the
        # identity is already bound to another user profile which would happen
        # e.g. in the following situation:
        #
        # - The user registered to the service through OmniAuth for the first
        #   time using this OmniAuth identity.
        # - Next time they came to the service, they created a new user account
        #   in Decidim using the registration form with another email address.
        # - Now, they sign in to the service using the manually created account.
        # - They go to the authorization view to authorize themselves through
        #   MSAD (which adds the authorization metadata information that might
        #   be required in order to perform actions).
        # - Now the person has two accounts, one of which is already bound to a
        #   user's OmniAuth identity.
        # - There is a conflict because we cannot bind the same identity to two
        #   different user profiles (which could lead to thefts).
        # - This method will notice it and the OmniAuth login information will
        #   not be stored to the user's authorization metadata.
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

        # The authorize_user! method will be performed when the sign in attempt
        # has been verified and the user has been identified or alternatively a
        # new identity has been created to them. The possibly configured SAML
        # attributes are stored against the authorization making it possible to
        # add action authorizer conditions based on the information passed from
        # AD. E.g. some processes might be only limited to specific users within
        # the organization belonging to a specific group.
        def authorize_user!(user)
          authorization = ::Decidim::Authorization.find_by(
            name: "#{tenant.name}_identity",
            unique_id: user_signature
          )
          if authorization
            raise AuthorizationBoundToOtherUserError if authorization.user != user
          else
            authorization = ::Decidim::Authorization.find_or_initialize_by(
              name: "#{tenant.name}_identity",
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

        # Keeps the user data in sync with the federation server after
        # everything else is done and the user is just aboud to be redirected
        # further to the next page after the successful login. This is called on
        # every successful login callback request.
        def update_user!(user)
          user_changed = false
          if user.email != verified_email
            user_changed = true
            user.email = verified_email
            user.skip_reconfirmation!
          end
          user.newsletter_notifications_at = Time.now if user_newsletter_subscription?(user)

          user.save! if user_changed
        end

        protected

        attr_reader :organization, :tenant, :oauth_hash

        def user_newsletter_subscription?(user)
          return false unless @new_user

          # Return if newsletter subscriptions are not configured
          return false unless tenant.registration_newsletter_subscriptions

          user.newsletter_notifications_at.nil?
        end

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
          @metadata_collector ||= tenant.metadata_collector_for(saml_attributes)
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
            "#{tenant.name.upcase}:#{user_identifier}:#{Rails.application.secrets.secret_key_base}"
          )
        end
      end
    end
  end
end
