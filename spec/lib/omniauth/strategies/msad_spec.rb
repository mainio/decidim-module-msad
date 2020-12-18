# frozen_string_literal: true

require "spec_helper"
require "omniauth/strategies/msad"

RSpec::Matchers.define :fail_with do |message|
  match do |actual|
    actual.redirect? && actual.location == /\?.*message=#{message}/
  end
end

# Silence the OmniAuth logger
# OmniAuth.config.logger = Logger.new("/dev/null")

module OmniAuth
  module Strategies
    describe MSAD, type: :strategy do
      include Rack::Test::Methods
      include OmniAuth::Test::StrategyTestCase

      def base64_file(filename)
        Base64.encode64(IO.read(file_fixture(filename)))
      end

      let(:certgen) { OmniAuth::Msad::Test::CertificateGenerator.new }
      let(:private_key) { certgen.private_key }
      let(:certificate) { certgen.certificate }

      let(:auth_hash) { last_request.env["omniauth.auth"] }
      let(:saml_options) do
        {
          idp_metadata_file: idp_metadata_file,
          idp_metadata_url: idp_metadata_url,
          sp_entity_id: sp_entity_id,
          certificate: certificate.to_pem,
          private_key: private_key.to_pem,
          security: security_options
        }
      end
      let(:security_options) { {} }
      let(:idp_metadata_file) { nil }
      let(:idp_metadata_url) { "https://login.microsoftonline.com/987f6543-1e0d-12a3-45b6-789012c345de/federationmetadata/2007-06/federationmetadata.xml" }
      let(:sp_entity_id) { "https://1.lvh.me/users/auth/msad/metadata" }
      let(:strategy) { [described_class, saml_options] }

      before do
        OmniAuth.config.full_host = "https://1.lvh.me"
      end

      describe "#initialize" do
        subject { get "/users/auth/msad/metadata" }

        shared_examples "an OmniAuth strategy" do
          it "applies the local options and the IdP metadata options" do
            expect(subject).to be_successful

            instance = last_request.env["omniauth.strategy"]

            expect(instance.options[:sp_entity_id]).to eq(
              "https://1.lvh.me/users/auth/msad/metadata"
            )
            expect(instance.options[:certificate]).to eq(certificate.to_pem)
            expect(instance.options[:private_key]).to eq(private_key.to_pem)
            expect(instance.options[:security]).to include(
              "authn_requests_signed" => true,
              "logout_requests_signed" => true,
              "logout_responses_signed" => true,
              "want_assertions_signed" => true,
              "want_assertions_encrypted" => false,
              "want_name_id" => false,
              "metadata_signed" => false,
              "embed_sign" => false,
              "digest_method" => XMLSecurity::Document::SHA256,
              "signature_method" => XMLSecurity::Document::RSA_SHA256,
              "check_idp_cert_expiration" => false,
              "check_sp_cert_expiration" => false
            )

            # Check the automatically set options
            expect(instance.options[:assertion_consumer_service_url]).to eq(
              "https://1.lvh.me/users/auth/msad/callback"
            )
            expect(instance.options[:sp_name_qualifier]).to eq(
              "https://1.lvh.me/users/auth/msad/metadata"
            )
            expect(instance.options[:idp_name_qualifier]).to eq(
              "https://sts.windows.net/987f6543-1e0d-12a3-45b6-789012c345de/"
            )

            # Check the most important metadata options
            expect(instance.options[:idp_entity_id]).to eq(
              "https://sts.windows.net/987f6543-1e0d-12a3-45b6-789012c345de/"
            )
            expect(instance.options[:name_identifier_format]).to eq(
              "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"
            )
            expect(instance.options[:idp_slo_target_url]).to eq(
              "https://login.microsoftonline.com/987f6543-1e0d-12a3-45b6-789012c345de/saml2"
            )
            expect(instance.options[:idp_sso_target_url]).to eq(
              "https://login.microsoftonline.com/987f6543-1e0d-12a3-45b6-789012c345de/saml2"
            )

            idp_cert = File.read(file_fixture("idp.crt"))
            expect(instance.options[:idp_cert]).to eq(
              # Remove the comments and newlines from the cert
              idp_cert.gsub(/-----[^\-]+-----/, "").gsub("\n", "")
            )
          end

          context "when the name identifier format is specified" do
            let(:saml_options) do
              {
                idp_metadata_file: idp_metadata_file,
                idp_metadata_url: idp_metadata_url,
                sp_entity_id: sp_entity_id,
                name_identifier_format: "urn:oasis:names:tc:SAML:2.0:nameid-format:transient"
              }
            end

            it "uses the configured name identifier format" do
              expect(subject).to be_successful

              instance = last_request.env["omniauth.strategy"]

              expect(instance.options[:name_identifier_format]).to eq(
                "urn:oasis:names:tc:SAML:2.0:nameid-format:transient"
              )
            end
          end

          context "when the security option is specified" do
            # This config wouldn't make any sense but it is just to test that
            # the configuration settings are changed to opposite than the
            # default values.
            let(:security_options) do
              {
                authn_requests_signed: false,
                logout_requests_signed: false,
                logout_responses_signed: false,
                want_assertions_signed: false,
                want_assertions_encrypted: true,
                want_name_id: true
              }
            end

            it "applies the security options according to the defined values" do
              expect(subject).to be_successful

              instance = last_request.env["omniauth.strategy"]

              expect(instance.options[:security]).to include(
                "authn_requests_signed" => false,
                "logout_requests_signed" => false,
                "logout_responses_signed" => false,
                "want_assertions_signed" => false,
                "want_assertions_encrypted" => true,
                "want_name_id" => true
              )
            end
          end
        end

        it_behaves_like "an OmniAuth strategy"
        it_behaves_like "an OmniAuth strategy" do
          let(:idp_metadata_file) { file_fixture("idp_metadata.xml") }
          let(:idp_metadata_url) { nil }
        end
      end

      describe "GET /users/auth/msad" do
        subject { get "/users/auth/msad" }

        it "signs the request" do
          expect(subject).to be_redirect

          location = URI.parse(last_response.location)
          query = Rack::Utils.parse_query location.query
          expect(query).to have_key("SAMLRequest")
          expect(query).to have_key("Signature")
          expect(query).to have_key("SigAlg")
          expect(query["SigAlg"]).to eq(XMLSecurity::Document::RSA_SHA256)

          # Check that the signature matches
          signature_query = Rack::Utils.build_query(
            "SAMLRequest" => query["SAMLRequest"],
            "SigAlg" => query["SigAlg"]
          )
          sign_algorithm = XMLSecurity::BaseDocument.new.algorithm(
            XMLSecurity::Document::RSA_SHA256
          )
          signature = private_key.sign(sign_algorithm.new, signature_query)
          expect(Base64.decode64(query["Signature"])).to eq(signature)
        end

        it "creates a valid SAML authn request" do
          expect(subject).to be_redirect

          location = URI.parse(last_response.location)
          expect(location.scheme).to eq("https")
          expect(location.host).to eq("login.microsoftonline.com")
          expect(location.path).to eq("/987f6543-1e0d-12a3-45b6-789012c345de/saml2")

          query = Rack::Utils.parse_query location.query

          deflated_xml = Base64.decode64(query["SAMLRequest"])
          xml = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(deflated_xml)
          request = REXML::Document.new(xml)
          expect(request.root).not_to be_nil

          acs = request.root.attributes["AssertionConsumerServiceURL"]
          dest = request.root.attributes["Destination"]
          ii = request.root.attributes["IssueInstant"]

          expect(acs).to eq("https://1.lvh.me/users/auth/msad/callback")
          expect(dest).to eq("https://login.microsoftonline.com/987f6543-1e0d-12a3-45b6-789012c345de/saml2")
          expect(ii).to match(/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/)

          issuer = request.root.elements["saml:Issuer"]
          expect(issuer.text).to eq("https://1.lvh.me/users/auth/msad/metadata")
        end
      end

      describe "POST /users/auth/msad/callback" do
        subject { last_response }

        let(:xml) { :saml_response }

        context "when the response is valid" do
          let(:saml_options) do
            {
              idp_metadata_url: idp_metadata_url,
              sp_entity_id: sp_entity_id,
              certificate: certificate,
              private_key: private_key,
              idp_cert: sign_certificate.to_pem
            }
          end

          let(:custom_saml_attributes) { [] }

          # Use local certificate and private key for signing because otherwise the
          # locally signed SAMLResponse's signature cannot be properly validated as
          # we cannot sign it using the actual environments private key which is
          # unknown.
          let(:sign_certgen) { OmniAuth::Msad::Test::CertificateGenerator.new }
          let(:sign_certificate) { sign_certgen.certificate }
          let(:sign_private_key) { sign_certgen.private_key }

          before do
            allow(Time).to receive(:now).and_return(
              Time.utc(2020, 9, 2, 6, 0, 0)
            )

            saml_response = base64_file("#{xml}.xml")

            post(
              "/users/auth/msad/callback",
              "SAMLResponse" => saml_response
            )
          end

          it "sets the info hash correctly" do
            expect(auth_hash["info"].to_hash).to eq(
              "email" => "matti.meikalainen@example.org",
              "first_name" => "Matti",
              "last_name" => "Meikalainen",
              "name" => "Matti Meikalainen",
              "nickname" => "mmeikalainen"
            )
          end

          it "sets the raw info to all attributes" do
            expect(auth_hash["extra"]["raw_info"].all.to_hash).to eq(
              "http://schemas.microsoft.com/identity/claims/tenantid" => ["999a8888-1a2b-11a1-11a1-111111a111ab"],
              "http://schemas.microsoft.com/identity/claims/objectidentifier" => ["555abcd5-a555-5a55-a5aa-a55555a555aa"],
              "http://schemas.microsoft.com/identity/claims/displayname" => ["mmeikalainen"],
              "http://schemas.microsoft.com/identity/claims/identityprovider" => ["live.com"],
              "http://schemas.microsoft.com/claims/authnmethodsreferences" => [
                "http://schemas.microsoft.com/ws/2008/06/identity/authenticationmethod/password",
                "http://schemas.microsoft.com/ws/2008/06/identity/authenticationmethod/unspecified"
              ],
              "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname" => ["Matti"],
              "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname" => ["Meikalainen"],
              "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress" => ["matti.meikalainen@example.org"],
              "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name" => ["mmeikalainen.onmicrosoft.com#EXT\#@example.onmicrosoft.com"],
              "Department" => ["Lauttasaari"],
              "PostalCode" => ["00210"],
              "DisplayName" => ["mmeikalainen"],
              "EmployeeID" => ["ABC123"],
              "fingerprint" => "D3:99:D4:73:A3:A3:AA:B1:89:5E:E3:7C:69:84:22:8D:88:EB:96:4C"
            )
          end

          describe "#response_object" do
            subject { instance.response_object }

            let(:instance) { last_request.env["omniauth.strategy"] }

            it "returns the response object" do
              expect(subject).to be_a(OneLogin::RubySaml::Response)
              expect(subject).to be_is_valid
            end
          end
        end

        context "when response is a logout response" do
          let(:relay_state) { "/relay/uri" }

          before do
            post "/users/auth/msad/slo", {
              SAMLResponse: base64_file("saml_logout_response.xml"),
              RelayState: relay_state
            }, "rack.session" => {
              "saml_transaction_id" => "_123456ab-1234-1a2b-cd3e-1a2b34567890"
            }
          end

          it "redirects to relaystate" do
            expect(last_response).to be_redirect
            expect(last_response.location).to eq("/relay/uri")
          end

          context "with a full HTTP URI as relaystate" do
            let(:relay_state) { "http://www.mainiotech.fi/vuln" }

            it "redirects to the root path" do
              expect(last_response.location).to eq("/")
            end
          end

          context "with a full HTTPS URI as relaystate" do
            let(:relay_state) { "https://www.mainiotech.fi/vuln" }

            it "redirects to the root path" do
              expect(last_response.location).to eq("/")
            end
          end

          context "with a non-protocol URI as relaystate" do
            let(:relay_state) { "//www.mainiotech.fi/vuln" }

            it "redirects to the root path" do
              expect(last_response.location).to eq("/")
            end
          end
        end

        shared_examples "replaced relay state" do
          it "adds root URI as the RelayState parameter to the response" do
            expect(last_response).to be_redirect

            location = URI.parse(last_response.location)
            query = Rack::Utils.parse_query location.query
            expect(query["RelayState"]).to eq("/")
          end
        end

        shared_examples "invalid relay states replaced" do
          context "with a full HTTP URI" do
            let(:relay_state) { "http://www.mainiotech.fi/vuln" }

            it_behaves_like "replaced relay state"
          end

          context "with a full HTTPS URI" do
            let(:relay_state) { "https://www.mainiotech.fi/vuln" }

            it_behaves_like "replaced relay state"
          end

          context "with a non-protocol URI" do
            let(:relay_state) { "//www.mainiotech.fi/vuln" }

            it_behaves_like "replaced relay state"
          end
        end

        context "when request is a logout request" do
          subject do
            post(
              "/users/auth/msad/slo",
              params,
              "rack.session" => {
                "saml_uid" => "mmeikalainen.onmicrosoft.com#EXT\#@example.onmicrosoft.com"
              }
            )
          end

          let(:params) { { "SAMLRequest" => base64_file("saml_logout_request.xml") } }

          context "when logout request is valid" do
            before { subject }

            it "redirects to logout response" do
              expect(last_response).to be_redirect
              expect(last_response.location).to match %r{https://login.microsoftonline.com/987f6543-1e0d-12a3-45b6-789012c345de/saml2}
            end
          end

          context "when RelayState is provided" do
            let(:params) do
              {
                "SAMLRequest" => base64_file("saml_logout_request.xml"),
                "RelayState" => relay_state
              }
            end
            let(:relay_state) { nil }

            before { subject }

            context "with a valid value" do
              let(:relay_state) { "/local/path/to/app" }

              it "adds the RelayState parameter to the response" do
                expect(last_response).to be_redirect

                location = URI.parse(last_response.location)
                query = Rack::Utils.parse_query location.query
                expect(query["RelayState"]).to eq(relay_state)
              end
            end

            it_behaves_like "invalid relay states replaced"
          end
        end

        context "when sp initiated SLO" do
          let(:params) { nil }

          before { post("/users/auth/msad/spslo", params) }

          it "redirects to logout request" do
            expect(last_response).to be_redirect
            expect(last_response.location).to match %r{https://login.microsoftonline.com/987f6543-1e0d-12a3-45b6-789012c345de/saml2}
          end

          context "when RelayState is provided" do
            let(:params) { { "RelayState" => relay_state } }
            let(:relay_state) { nil }

            context "with a valid value" do
              let(:relay_state) { "/local/path/to/app" }

              it "adds the RelayState parameter to the response" do
                expect(last_response).to be_redirect

                location = URI.parse(last_response.location)
                query = Rack::Utils.parse_query location.query
                expect(query["RelayState"]).to eq(relay_state)
              end
            end

            it_behaves_like "invalid relay states replaced"
          end
        end
      end

      describe "GET /users/auth/msad/metadata" do
        subject { get "/users/auth/msad/metadata" }

        let(:response_xml) { Nokogiri::XML(last_response.body) }
        let(:request_attribute_nodes) do
          response_xml.xpath(
            "//md:EntityDescriptor//md:SPSSODescriptor//md:AttributeConsumingService//md:RequestedAttribute"
          )
        end
        let(:request_attributes) do
          request_attribute_nodes.map do |node|
            {
              friendly_name: node["FriendlyName"],
              name: node["Name"]
            }
          end
        end

        it "adds the correct request attributes" do
          expect(subject).to be_successful
          expect(request_attributes).to match_array([])
        end

        context "when IdP metadata URL is not available" do
          let(:idp_metadata_url) { nil }

          it "responds to the metadata request" do
            expect(subject).to be_successful
          end
        end
      end
    end
  end
end
