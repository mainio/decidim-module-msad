# frozen_string_literal: true

require "decidim/dev"
require "omniauth/msad/test"
require "webmock"

require "decidim/msad/test/runtime"

require "simplecov" if ENV["SIMPLECOV"] || ENV["CODECOV"]
if ENV["CODECOV"]
  require "codecov"
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

ENV["ENGINE_ROOT"] = File.dirname(__dir__)

Decidim::Dev.dummy_app_path =
  File.expand_path(File.join(__dir__, "decidim_dummy_app"))

require_relative "base_spec_helper"

Decidim::Msad::Test::Runtime.initializer do
  # Silence the OmniAuth logger
  OmniAuth.config.logger = Logger.new("/dev/null")

  # Configure the MSAD module with two tenants
  Decidim::Msad.configure do |config|
    # Using default name: msad
    config.idp_metadata_url = "https://login.microsoftonline.com/987f6543-1e0d-12a3-45b6-789012c345de/federationmetadata/2007-06/federationmetadata.xml"
    config.sp_entity_id = "http://1.lvh.me/users/auth/msad/metadata"
    config.auto_email_domain = "1.lvh.me"
  end
  Decidim::Msad.configure do |config|
    config.name = "other"
    config.idp_metadata_url = "https://login.microsoftonline.com/876f5432-1e0d-12a3-45b6-789012c345de/federationmetadata/2007-06/federationmetadata.xml"
    config.sp_entity_id = "http://2.lvh.me/users/auth/other/metadata"
    config.auto_email_domain = "2.lvh.me"
  end
end

# Respond to the metadata request with a stubbed request to avoid external
# HTTP calls. This needs to be mocked already here because the omniauth
# initializer is already run at the application startup which calls the metadata
# URL.
base_path = File.expand_path(File.join(__dir__, ".."))
metadata_path = File.expand_path(
  File.join(base_path, "spec", "fixtures", "files", "idp_metadata.xml")
)
WebMock.enable!
WebMock::StubRegistry.instance.register_request_stub(
  WebMock::RequestStub.new(
    :get,
    "https://login.microsoftonline.com/987f6543-1e0d-12a3-45b6-789012c345de/federationmetadata/2007-06/federationmetadata.xml"
  )
).to_return(status: 200, body: File.new(metadata_path), headers: {})
WebMock::StubRegistry.instance.register_request_stub(
  WebMock::RequestStub.new(
    :get,
    "https://login.microsoftonline.com/876f5432-1e0d-12a3-45b6-789012c345de/federationmetadata/2007-06/federationmetadata.xml"
  )
).to_return(status: 200, body: File.new(metadata_path), headers: {})

Decidim::Msad::Test::Runtime.load_app

# Add the test templates path to ActionMailer
ActionMailer::Base.prepend_view_path(
  File.expand_path(File.join(__dir__, "fixtures", "mailer_templates"))
)

RSpec.configure do |config|
  # Make it possible to sign in and sign out the user in the request type specs.
  # This is needed because we need the request type spec for the omniauth
  # callback tests.
  config.include Devise::Test::IntegrationHelpers, type: :request

  config.before do
    # The metadata request needs to be stubbed for a second time in order for
    # the stubbed request to be also defined for the individual specs.
    stub_request(
      :get,
      "https://login.microsoftonline.com/987f6543-1e0d-12a3-45b6-789012c345de/federationmetadata/2007-06/federationmetadata.xml"
    ).to_return(status: 200, body: File.new(metadata_path), headers: {})
  end
end
