# Decidim::Msad - Integrate Decidim to Microsoft Active Directory (AD)

[![Build Status](https://travis-ci.com/mainio/decidim-module-msad.svg?branch=master)](https://travis-ci.com/mainio/decidim-module-msad)
[![codecov](https://codecov.io/gh/mainio/decidim-module-msad/branch/master/graph/badge.svg)](https://codecov.io/gh/mainio/decidim-module-msad)
[![Crowdin](https://badges.crowdin.net/decidim-msad/localized.svg)](https://crowdin.com/project/decidim-msad)

A [Decidim](https://github.com/decidim/decidim) module to add Microsoft Active
Directory (AD) authentication to Decidim as a way to authenticate and authorize
the users. Can be integrated to Azure AD or ADFS running on the organization's
own server using the SAML authentication flow (SAML 2.0).

This allows Decidim users to log in to Decidim using their organization's Active
Directory accounts, which are usually the same accounts they use to log in to
their computers. In addition, these users can also be authorized with the data
available in the AD server (person's department, location, groups, etc.).

The gem has been developed by [Mainio Tech](https://www.mainiotech.fi/).

Active Directory is a Microsoft product and is not related to this gem in any
way, nor do they provide technical support for it. Please contact the gem
maintainers in case you find any issues with it.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "decidim-msad"
```

And then execute:

```bash
$ bundle
```

After installation, you can add the initializer running the following command:

```bash
$ bundle exec rails generate decidim:msad:install
```

You need to set the following configuration options inside the initializer:

- `:idp_metadata_url` - The metadata URL for the identity provider which is the
  federation server's metadata URL.
- `:sp_entity_id` - The service provider entity ID, i.e. your applications
  entity ID used to identify the service at the Active Directory SAML identity
  provider.
  * Set this to the same ID that you use for the metadata sent to the federation
    server.
  * Default: depends on the application's URL, e.g.
    `https://www.example.org/users/auth/msad/metadata`

Optionally you can also configure the module with the following options:

- `:auto_email_domain` - Defines the auto-email domain in case the user's domain
  is not stored at the federation server. In case this is not set (default),
  emails will not be auto-generated and users will need to enter them manually
  in case the federation server does not report them.
  * The auto-generated email format is similar to the following string:
    `msad-756be91097ac490961fd04f121cb9550@example.org`. The email will
    always have the `msad-` prefix and the domain part is defined by the
    configuration option.
  * In case this is not defined, the organization's host will be used as the
    default.
- `:certificate_file` - Path to the local certificate included in the metadata
  sent to the federation server with the service provider metadata. This is
  optional as Azure AD or ADFS do not force encrypting the SAML assertion data.
- `:private_key_file` - Path to the local private key (corresponding to the
  certificate). Will be used to decrypt messages coming from the federation
  server. As the `:certificate_file` option, this is also optional.
- `:metadata_attributes` - Defines the SAML attributes that will be stored in
  the user's associated authorization record's `metadata` field in Decidim.
  These are read from the SAML authentication response and stored once the user
  is identified or a new user record is created. See an example in the
  initializer file.
- `:sp_metadata` - Extra metadata that you can add to the service provider
  metadata XML file. See an example in the initializer file.

The install generator will also enable the Active Directory authentication
method for OmniAuth by default by adding these lines your `config/secrets.yml`:

```yml
default: &default
  # ...
  omniauth:
    # ...
    msad:
      enabled: false
      metadata_url:
      icon: account-login
development:
  # ...
  omniauth:
    # ...
    msad:
      enabled: true
      metadata_url:
      icon: account-login
```

This will enable the Active Directory authentication for the development
environment only. In case you want to enable it for other environments as well,
apply the OmniAuth configuration keys accordingly to other environments as well.

Please also note that you will need to define the metadata URL for the identity
provider (the federation server, either Azure AD or ADFS) in order for the
integration to work.

The example configuration will set the `account-login` icon for the the
authentication button from the Decidim's own iconset. In case you want to have a
better and more formal styling for the sign in button, you will need to
customize the sign in / sign up views.

## Usage

After the installation steps, you will need to enable the Active Directory
authorization from Decidim's system management panel. After enabled, you can
start using it.

This gem also provides a Active Directory sign in method which will
automatically authorize the user accounts. In case the users already have an
account, they can still authorize themselves using the Active Directory
authorization.

## Customization

For some specific needs, you may need to store extra metadata for the Active
Directory authorization or add new authorization configuration options for the
authorization.

This can be achieved by applying the following configuration to the module
inside the initializer described above:

```ruby
# config/initializers/msad.rb

Decidim::Msad.configure do |config|
  # ... keep the default configuration as is ...
  # Add this extra configuration:
  config.workflow_configurator = lambda do |workflow|
    # When expiration is set to 0 minutes, it will never expire.
    workflow.expires_in = 0.minutes
    workflow.action_authorizer = "CustomMsadActionAuthorizer"
    workflow.options do |options|
      options.attribute :custom_option, type: :string, required: false
    end
  end
  config.metadata_collector_class = CustomMsadMetadataCollector
end
```

For the workflow configuration options, please refer to the
[decidim-verifications documentation](https://github.com/decidim/decidim/tree/master/decidim-verifications).

For the custom metadata collector, please extend the default class as follows:

```ruby
# frozen_string_literal: true

class CustomMsadMetadataCollector < Decidim::Msad::Verification::MetadataCollector
  def metadata
    super.tap do |data|
      # You can access the SAML attributes using the `saml_attributes` accessor
      # which is an instance of `OneLogin::RubySaml::Attributes`. It has the
      # instance methods `#single` for fetching single attributes and `#multi`
      # for fetching attributes that have multiple values.
      computer_model = saml_attributes.single("computer_model")
      unless computer_model.blank?
        # This will actually add the data to the user's authorization metadata
        # hash.
        data[:computer] = "Model: #{computer_model}"
      end
    end
  end
end
```

Please note that if you don't need to do very customized metadata collection,
customizing the metadata collector should not be generally necessary. Instead,
you can use the `metadata_attributes` configuration option which allows you to
define the SAML attribute keys and their associated metadata keys to be stored
with the user's authorization. Customization of the metadata collector is only
necessary in cases where you need to calculate new values or process the
original values somehow prior to saving them to the user's metadata.

## Contributing

See [Decidim](https://github.com/decidim/decidim).

### Testing

To run the tests run the following in the gem development path:

```bash
$ bundle
$ DATABASE_USERNAME=<username> DATABASE_PASSWORD=<password> bundle exec rake test_app
$ DATABASE_USERNAME=<username> DATABASE_PASSWORD=<password> bundle exec rspec
```

Note that the database user has to have rights to create and drop a database in
order to create the dummy test app database.

In case you are using [rbenv](https://github.com/rbenv/rbenv) and have the
[rbenv-vars](https://github.com/rbenv/rbenv-vars) plugin installed for it, you
can add these environment variables to the root directory of the project in a
file named `.rbenv-vars`. In this case, you can omit defining these in the
commands shown above.

### Test code coverage

If you want to generate the code coverage report for the tests, you can use
the `SIMPLECOV=1` environment variable in the rspec command as follows:

```bash
$ SIMPLECOV=1 bundle exec rspec
```

This will generate a folder named `coverage` in the project root which contains
the code coverage report.

### Localization

If you would like to see this module in your own language, you can help with its
translation at Crowdin:

https://crowdin.com/project/decidim-msad

## License

See [LICENSE-AGPLv3.txt](LICENSE-AGPLv3.txt).
