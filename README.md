# Decidim::Msad - Integrate Decidim to Microsoft Active Directory (AD)

[![Build Status](https://github.com/mainio/decidim-module-msad/actions/workflows/ci_msad.yml/badge.svg)](https://github.com/mainio/decidim-module-msad/actions)
[![codecov](https://codecov.io/gh/mainio/decidim-module-msad/branch/master/graph/badge.svg)](https://codecov.io/gh/mainio/decidim-module-msad)
[![Crowdin](https://badges.crowdin.net/decidim-msad/localized.svg)](https://crowdin.com/project/decidim-msad)

> [!IMPORTANT]
> This repository is no longer be maintained. This module has been deprecated in
> favor of a new
> [Entra ID module](https://github.com/mainio/decidim-module-entraid). Please
> use that module instead or migrate to that module in case you have been using
> this module.

![Decidim MSAD](decidim-msad.png)

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
  * If your ADFS server does not provide a public metadata URL, you can also
    point to a local file with the `:idp_metadata_file` option (see below). When
    using `:idp_metadata_file` it will get priority over `:idp_metadata_url`.
    Only one of these can be used per tenant.
- `:sp_entity_id` - The service provider entity ID, i.e. your applications
  entity ID used to identify the service at the Active Directory SAML identity
  provider.
  * Set this to the same ID that you use for the metadata sent to the federation
    server.
  * Default: depends on the application's URL, e.g.
    `https://www.example.org/users/auth/msad/metadata`

Optionally you can also configure the module with the following options:

- `:name` - The name of the AD provider. Only lowercase characters and
  underscores are allowed. Defaults to "msad" with only a single tenant. With
  multiple tenants, each tenant needs to have an individual distinct name.
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
- `:disable_spslo` - A boolean indicating if the service provider initiated SAML
  logout (SPSLO) should be disabled. ADFS supports SAML sign out only when the
  sign out requests are signed which requires configuring a certificate and a
  private key for the ADFS tenant. For Azure AD, this works by default and does
  not require any extra configuration. By default, this configuration is set to
  `false` assuming you want to enable the SAML sign out requests to Azure AD or
  ADFS when the user signs out of Decidim. In some circumstances you might not
  want the user to perform a sign out request to the AD federation server.
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

### Connecting with multiple tenants

In case you want to integrate with multiple Azure AD or ADFS tenants, you can
duplicate the configuration block in the sample configuration as follows:

```ruby
# First tenant
Decidim::Msad.configure do |config|
  config.name = "msad"
  # => Configuration for the "msad" tenant (copy the sample config here)
end

# Second tenant
Decidim::Msad.configure do |config|
  config.name = "otherad"
  # => Configuration for the "otherad" tenant (copy the sample config here)
end
```

Please note that in this case you will need to configure an individual name for
each tenant. If you fail to do this, you may see obscure error messages when
trying to start the server.

You should always begin with a single tenant to get a better understanding of
how to configure this module and Azure AD or ADFS. Once you are ready with the
first tenant, go ahead and configure another one.

**IMPORTANT:** The beginning of the tenant names cannot match with each other.
Please use fully distinct names for each tenant. Consider the following examples
for further instructions:

- **Correct**:
  * First tenant: `config.name = "msad"`
  * Second tenant: `config.name = "otherad"`
- Incorrect:
  * ~~First tenant: `config.name = "msad"`~~
  * ~~Second tenant: `config.name = "msad_other"`~~ (the first tenant's name
    would match with this string when compared from the beginning of the string)

Once configured, please note that for the other tenant the authentication
endpoint urls shown in this document need to be modified according to the
tenant's name. By default, the tenant name for a single tenant is `msad` in
which case the authentication URLs look as follows:

`https://www.example.org/users/auth/msad/***`

When you configure the tenant's name to something else than the default, these
URLs will change accordingly. With the configuration example above, they would
be as follows:

- `https://www.example.org/users/auth/msad/***`
- `https://www.example.org/users/auth/otherad/***`

## Configuring the federation server

For configuring the federation server, you will need to send the AD federation
server administrator some data from the Decidim's side. After installing the
module and configuring your entity ID, possible SP certificate and any additonal
SP metadata you want to send, you can send the federation side's administrator
the following URL to your instance in order for them to get the necessary data
for joining the system at their side:

https://your-organization.org/users/auth/msad/metadata

Change the domain accordingly to your instance and make sure you see an XML file
in that URL when you request it. This is the SAML metadata you will need to send
to the other side.

After the other side is configured, you can start using the integration at
Decidim's side. If you already know the AD federation server's metadata URL in
advance, you can already configure it at this point but obviously the sign ins
won't work until the federation server is configured correctly. The metadata
URLs for the federation servers (either Azure AD or ADFS) should look as
follows:

- **Azure AD**: https://login.microsoftonline.com/123a4567-8b90-12a3-45b6-789012a345bc/federationmetadata/2007-06/federationmetadata.xml?appid=ab1c2d3e-45fa-123b-4cd5-e678fabc90d1
- **ADFS**: https://adfs.your-organization.org/FederationMetadata/2007-06/FederationMetadata.xml

You can configure this URL to the module's `:idp_metadata_url` configuration as
explained previously in this document. Before giving it a try, you of course
need to configure the federation side to handle your requests.

If you don't know the metadata URL, please ask it from the federation server
administrator after you have sent your service provider (SP) metadata to them.
If you don't have a public metadata URL, you can use the `:idp_metadata_file`
option to point to a local metadata file on the Decidim server. Always prefer
the public URL because it updates automatically if the server configurations are
updated.

### Configuring Azure AD

To configure Azure AD, follow these steps:

1. Go to your Decidim instance's metadata URL (explained previously in this
   document) and save the metadata XML to a file with the `.xml` extension on
   your computer.
2. In Azure, may be obvious but deploy the Azure AD instance if you haven't done
   so yet.
3. Under the Azure Active Directory, go to "Enterprise Applications".
4. Click "+ New application" and from the top of the view that opens, click
   "+ Create your own application".
5. Give the name of your app based on your application's name, e.g.
   "Your Organization Decidim" and leave the "Integrate any other application
   you don't find in the gallery" option selected.
6. Go to the "Single sign-on" tab and select "SAML" as the Select a single
   sign-on method.
7. From the top of the view, click "Upload metadata" and pick the Decidim
   instance's metadata XML file you saved in the beginning. Some of the required
   properties should be automatically filled but for those fields that are not,
   define the following (optional):
   * Sign on URL: https://your-organization.org/users/auth/msad
   * Relay State: https://your-organization.org/
8. Click "Save" and wait for the configurations to update.
9. Click "Edit" under the "User Attributes & Claims" section and define the
   attributes shown in the table below. Leave the "Unique User Identifier
   (Name ID)" claim untouched unless you know what you are doing.
10. Once done with the claims, copy the "App Federation Metadata Url" from the
    "SAML Signing Certificate" section of the Single sign-on view and configure
    it to the Decidim module's `:idp_metadata_url` configuration of your Decidim
    instance as explained in this document. If you don't see the metadata URL
    in this section, wait for a moment for the application to deploy at Azure.
12. After the single sign-on configuration, decide if you want to assign users
    manually to this application or let every user sign in to the application.
    If you want to provide access to all users in your Azure AD, go to the
    "Properties" tab of your Enterprise Application and change the "User
    assignment required?" configuration to "No".
13.  Test that the integration is working correctly.

These are the attributes you will need to configure for the "User Attributes &
Claims" section (some of these should be already pre-defined by Azure):

| Name         | NameSpace                                              | Source    | Source attribute       |
| ------------ | ------------------------------------------------------ | --------- | ---------------------- |
| emailaddress | http​://schemas.xmlsoap.org/ws/2005/05/identity/claims  | Attribute | user.mail              |
| name         | http​://schemas.xmlsoap.org/ws/2005/05/identity/claims  | Attribute | user.userprincipalname |
| givenname    | http​://schemas.xmlsoap.org/ws/2005/05/identity/claims  | Attribute | user.givenname         |
| surname      | http​://schemas.xmlsoap.org/ws/2005/05/identity/claims  | Attribute | user.surname           |
| displayname  | http​://schemas.microsoft.com/identity/claims           | Attribute | user.displayname       |

These are the minimum claims to be passed. You can also pass extra claims and
store them in the user's authorization metadata as explained in the
[Customization](#customization) section of this document. This may be useful
e.g. if you want to limit some sections of your service only to specific users
using Decidim's action authorizers.

### Configuring ADFS

ADFS does not generally undestand the SAML metadata very well and it does not
provide any further information about what might be wrong with the SAML
metadata XML. Therefore, the metadata you will see in the Decidim's metadata URL
will most likely not work when trying to directly import it to ADFS unless you
figure out what is missing from it and add it using the `:sp_metadata`
configuration (if you figure it out, do let us know). This seems to be a rather
common problem with ADFS using the SAML based relying party trusts.

To configure ADFS, follow these steps:

1. Open your Decidim instance's metadata url as specified above in order to get
   the required data from it.
2. On the ADFS server, open AD FS Management and select "Add Relying Party
   Trust" under "Relying Party Trusts".
3. For the data source, select "Enter data about the relying party manually".
4. For the "Display name" set whatever your instance is called.
5. For profile, select "AD FS Profile" which allows connecting with SAML.
6. Bypass the ceritifcate configuration unless you have configured an SP
   certificate in the module's configuration. Consult the ADFS administrator to
   get further information about the organization's security policies regarding
   this.
7. In the URL configuration, select "Enable support for the SAML 2.0 WebSSO
   protocol" and provide the following URL as the service URL (modified with
   your instance's domain):
   https://your-organization.org/users/auth/msad/callback
8. In the relying party trust identifier section, add the following URL:
   https://your-organization.org/users/auth/msad/metadata. Note that if you have
   customized the SAML entity ID for your instance, use that insted. You should
   see the correct value from your instance's metadata URL.
9. In the final step, leave "Open the Edit Claim Rules dialog" checked and
   proceed to configuring the claims.
10. Click "Add Rule" and pick "Send LDAP Attributes as Claims" as the claim rule
    template.
11. Give the rule name "SAMLAttributes" and configure the values as shown in the
    table below.
12. Add a transform rule by selecting "Transform an Incoming Claim" as the claim
    rule template. For the transform rule, define the following properties:
    * Claim rule name: `NameID Transform`
    * Incoming claim type: `Name ID`
    * Outgoing claim type: `Name ID`
    * Outgoing name ID format: `Email`
    * Pass through all claim values
13. Change the relying party trust secure hash algorithm to SHA-256 under the
    relying party's "Properties" window's "Advanced" tab.

These are the attributes you will need to configure for the "SAMLAttributes"
rule:

| LDAP Attribute      | Outgoing Claim Type                                      |
| ------------------- | -------------------------------------------------------- |
| E-Mail-Addresses    | Name ID                                                  |
| E-Mail-Addresses    | E-Mail Address                                           |
| User-Principal-Name | Name                                                     |
| Given-Name          | Given Name                                               |
| Surname             | Surname                                                  |
| DisplayName         | http​://schemas.microsoft.com/identity/claims/displayname |

The claims should be passed back to Decidim with the following schema names:

- E-Mail Address: http​://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress
- Name: http​://schemas.xmlsoap.org/ws/2005/05/identity/claims/name
- Given Name: http​://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname
- Surname: http​://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname
- DisplayName: http​://schemas.microsoft.com/identity/claims/displayname

If this is not the case for a reason or another, adjust the "Outgoing Claim
Type" to match these values.

These are the minimum claims to be passed. You can also pass extra claims and
store them in the user's authorization metadata as explained in the
[Customization](#customization) section of this document. This may be useful
e.g. if you want to limit some sections of your service only to specific users
using Decidim's action authorizers.

After the ADFS side is configured, change the `:idp_metadata_url` to match the
ADFS server's metadata URL if you haven't configured it yet. The format of the
URL should look similar to this:

https://adfs.your-organization.org/FederationMetadata/2007-06/FederationMetadata.xml

If your ADFS server is not configured to serve the metadata file publicly, you
will need to manually download the metadata file from the server, store it on
the Decidim server and then use the `:idp_metadata_file` option to point the
module's tenant configurations to that file.

#### Debugging the SAML responses

If your ADFS integration is not working properly and you will get login errors,
the first thing to check is the SAML response data passed from the ADFS server.
To do this, temporarily enable POST data logging on your server in order to
inspect the SAML responses from the ADFS server. Once you see the responses in
your logs, you can convert them to human readable XML using the following Ruby
code:

```ruby
require "ruby-saml"

idp_metadata_parser = OneLogin::RubySaml::IdpMetadataParser.new
settings = idp_metadata_parser.parse_remote("IDP_METADATA_URL_HERE")
raw_response = CGI.unescape("ENCODED_SAMLRESPONSE_POST_DATA")
response = OneLogin::RubySaml::Response.new(raw_response, { settings: settings })
puts response.document.to_s.inspect
```

This will print the SAMLResponse in human readable XML for further inspection.

#### Error: "Authentication failed or cancelled. Please try again."

If you see the SAML StatusCode
`urn:oasis:names:tc:SAML:2.0:status:InvalidNameIDPolicy` in the SAML response
data, it can mean that the ADFS server is not passing the SPNameQualifier value
as a claim back to the Decidim instance. In order to fix this, add a new claim
rule and select "Send Claims Using a Custom Rule". Give the rule name
"SPNameQualifier" and define the following in the "Custom rule" field:

```
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"]
=> issue(Type = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier", Issuer = c.Issuer, OriginalIssuer = c.OriginalIssuer, Value = c.Value, ValueType = c.ValueType, Properties["http://schemas.xmlsoap.org/ws/2005/05/identity/claimproperties/format"] = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress", Properties["http://schemas.xmlsoap.org/ws/2005/05/identity/claimproperties/spnamequalifier"] = "YOUR_ENTITY_ID_HERE");
```

In the rule, replace `YOUR_ENTITY_ID_HERE` with the entity ID of your instance
which should be `https://your-organization.org/users/auth/msad/metadata` with
the default configurations.

Also, you need to configure the email address to be sent as the NameID property
as described before. Make sure the NameID passed in the requests is the user's
email address.

Alternatively, you could also try to configure a different NameID format from
the ADFS side and specify the format for this module using the following
configuration in the initializer:

```ruby
# config/initializers/msad.rb

Decidim::Msad.configure do |config|
  # ... keep the default configuration as is ...
  # Add this extra configuration:
  config.extra = {
    # Specify the actual name identifier format the ADFS server is set to serve.
    # Should be one of the following:
    # - urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress
    # - urn:oasis:names:tc:SAML:2.0:nameid-format:persistent
    # - urn:oasis:names:tc:SAML:2.0:nameid-format:transient
    # - urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified
    name_identifier_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
  }
end
```

Note that the NameID field you configure at the ADFS side is used to uniquely
identify the users, so it should be unique per user and at least somewhat
permanent for all users.

#### Error: Sign in attempt failed through MSAD because "Invalid ticket".

In case you see an "Invalid ticket" error durign your login, make sure that you
have gone through the previous "Authentication failed or cancelled". After this,
check that your entity ID is correct in the custom rule and matches the entity
ID you see in the metadata.

#### Error: The authentication request was not handled within an allowed timeframe. Please try again.

In case you see this error, it could be that your server's and the ADFS server's
clocks are not perfectly in sync. You can try allowing clock drift for the
module which will accept callback requests within this configured drift. To
configure the clock drift, you can define the following "extra" configuration
in the initializer:

```ruby
# config/initializers/msad.rb

Decidim::Msad.configure do |config|
  # ... keep the default configuration as is ...
  # Add this extra configuration:
  config.extra = {
    # Define the allowed clock drift between your server and ADFS (in seconds)
    allowed_clock_drift: 30
  }
end
```

#### Error on logout (ADFS): "An Error Occurred"

In case sign in is working properly but sign out is not, it can be because of
multiple reasons:

- ADFS requires the SAML sign out requests to be signed which is only possible
  when you have configured the certificate and private key for the tenant. If
  you don't do this, SP initiated sign out requests are not possible.
- The NameID format might be incorrect during the sign out request. If this
  happens, you can try different formats using the `configs.extra` options (in
  particular, the `name_identifier_format` option explained in the
  authentication failure error).
  * The NameID format needs to match what ADFS is expecting during the sign out
    request and what is used to sign the user in. Otherwise, this module will
    use the first NameID format available in the metadata which might not be the
    correct one.

If you cannot configure the certificate and private key, you can disable the
sign out requests completely using the following configuration option:

```ruby
# config/initializers/msad.rb

Decidim::Msad.configure do |config|
  # ... keep the default configuration as is ...
  # Add this extra configuration:
  config.disable_spslo = true
end
```

Note that when the SPSLO requests are disabled, the user's session will be left
open on the ADFS server. In some circumstances this is desired as the user's
browser could be configured to automatically sign the user in with ADFS in which
case the sign out request to ADFS would have no effect.

## Usage

After the installation and configuration steps, you will need to enable the
Active Directory sign in method and authorization from Decidim's system
management panel. After enabled, you can start using it.

The Active Directory sign in method shipped with this gem will automatically
authorize the user accounts that signed in through AD. In case the users already
have an account, they can still authorize their existing accounts using the
Active Directory authorization if they want to avoid generating multiple user
accounts. This happens from the authorizations section of the user profile
pages.

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
