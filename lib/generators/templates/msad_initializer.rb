# frozen_string_literal: true

Decidim::Msad.configure do |config|
  # Define the name for the tenant. Only lowercase characters and underscores
  # are allowed. If you only have a single AD tenant, you don't need to
  # configure its name. When not configured, it will default to "msad". When you
  # want to connect to multiple tenants, you will need to define a unique name
  # for each tenant.
  # config.name = "msad"

  # Define the IdP metadata URL through the secrets
  config.idp_metadata_url = Rails.application.secrets.omniauth[:msad][:metadata_url]
  # If there is no public metadata URL, alternatively you can define the IdP
  # metadata file through the secrets. Always prefer the URL configuration
  # because it updates automatically in case something changes on the server.
  # config.idp_metadata_file = Rails.application.secrets.omniauth[:msad][:metadata_file]

  # Define the service provider entity ID:
  # config.sp_entity_id = "https://www.example.org/users/auth/msad/metadata"
  # Or define it in your application configuration and apply it here:
  # config.sp_entity_id = Rails.application.config.msad_entity_id
  # Enable automatically assigned emails
  config.auto_email_domain = "example.org"

  # Subscribe new users automatically to newsletters (default false).
  #
  # IMPORANT NOTE:
  # Legally it should be always a user's own decision if the want to subscribe
  # to any newsletters or not. Before enabling this, make sure you have your
  # legal basis covered for enabling it. E.g. for internal instances within
  # organizations, it should be generally acceptable but please confirm that
  # from the legal department first!
  # config.registration_newsletter_subscriptions = true

  # Configure the SAML attributes that will be stored in the user's
  # authorization metadata.
  # config.metadata_attributes = {
  #   display_name: "http://schemas.microsoft.com/identity/claims/displayname",
  #   given_name: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname",
  #   surname: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname",
  #   birthday: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/dateofbirth",
  #   postal_code: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/postalcode",
  #   mobile_phone: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/mobilephone",
  #   groups: { name: "http://schemas.microsoft.com/ws/2008/06/identity/claims/groups", type: :multi }
  # }

  # You can define extra service provider metadata that will show up in the
  # metadata URL.
  # config.sp_metadata = [
  #   {
  #     name: "Organization",
  #     children: [
  #       {
  #         name: "OrganizationName",
  #         attributes: { "xml:lang" => "en-US" },
  #         content: "Acme"
  #       },
  #       {
  #         name: "OrganizationDisplayName",
  #         attributes: { "xml:lang" => "en-US" },
  #         content: "Acme Corporation"
  #       },
  #       {
  #         name: "OrganizationURL",
  #         attributes: { "xml:lang" => "en-US" },
  #         content: "https://en.wikipedia.org/wiki/Acme_Corporation"
  #       }
  #     ]
  #   },
  #   {
  #     name: "ContactPerson",
  #     attributes: { "contactType" => "technical" },
  #     children: [
  #       {
  #         name: "GivenName",
  #         content: "John Doe"
  #       },
  #       {
  #         name: "EmailAddress",
  #         content: "jdoe@acme.org"
  #       }
  #     ]
  #   }
  # ]
end
