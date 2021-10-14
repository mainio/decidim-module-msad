# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Msad
    # Tests the controller as well as the underlying SAML integration that the
    # OmniAuth strategy is correctly loading the attribute values from the SAML
    # response. Note that this is why we are using the `:request` type instead
    # of `:controller`, so that we get the OmniAuth middleware applied to the
    # requests and the MSAD OmniAuth strategy to handle our generated
    # SAMLResponse.
    describe OmniauthCallbacksController, type: :request do
      let(:tenant) { Decidim::Msad.tenants.first }
      let(:organization) { create(:organization) }

      # For testing with signed in user
      let(:confirmed_user) do
        create(:user, :confirmed, organization: organization)
      end

      before do
        # Make the time validation of the SAML response work properly
        allow(Time).to receive(:now).and_return(
          Time.utc(2020, 9, 2, 6, 0, 0)
        )

        # Configure the metadata attributes to be collected
        tenant.metadata_attributes = {
          name: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
          first_name: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname",
          last_name: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname",
          nickname: "http://schemas.microsoft.com/identity/claims/displayname",
          groups: { name: "http://schemas.microsoft.com/ws/2008/06/identity/claims/groups", type: :multi },
          date_of_birth: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/dateofbirth",
          postal_code: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/postalcode",
          phone: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/mobilephone",
          department: "Department",
          location: "Location",
          employee_number: "EmployeeID"
        }

        # Reconfigure the OmniAuth strategy before the callback phase to
        # override the assertion consumer service URL. This is needed in order
        # to pass the SAML validations with the "http" URLs (without "https").
        OmniAuth.config.before_callback_phase do |env|
          strategy = env["omniauth.strategy"]
          strategy.options[:assertion_consumer_service_url] = "http://1.lvh.me/users/auth/msad/callback"
        end

        # Set the correct host
        host! organization.host
      end

      after do
        # Reset the metadata attributes back to defaults
        tenant.metadata_attributes = {}

        # Reset the before_callback_phase for the other tests
        OmniAuth.config.before_callback_phase {}
      end

      describe "GET msad" do
        let(:user_identifier) { "mmeikalainen.onmicrosoft.com#EXT\#@example.onmicrosoft.com" }
        let(:saml_attributes_base) do
          {
            "http://schemas.microsoft.com/identity/claims/tenantid" => ["999a8888-1a2b-11a1-11a1-111111a111ab"],
            "http://schemas.microsoft.com/identity/claims/objectidentifier" => ["555abcd5-a555-5a55-a5aa-a55555a555aa"],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name" => ["Matti Mainio"],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname" => ["Matti"],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname" => ["Mainio"],
            "http://schemas.microsoft.com/identity/claims/displayname" => ["mama"]
          }
        end
        let(:saml_attributes) do
          {
            "http://schemas.microsoft.com/ws/2008/06/identity/claims/groups" => %w(Managers HR),
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/dateofbirth" => ["1985-07-15"],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/postalcode" => ["00210"],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/mobilephone" => ["123456"],
            "Department" => ["IT"],
            "Location" => ["Helsinki"],
            "EmployeeID" => ["ABC123"]
          }
        end
        let(:saml_response) do
          attrs = saml_attributes_base.merge(saml_attributes)
          resp_xml = generate_saml_response(attrs)
          Base64.strict_encode64(resp_xml)
        end

        it "creates a new user record with the returned SAML attributes" do
          omniauth_callback_get

          user = User.last

          expect(user.name).to eq("Matti Mainio")
          expect(user.nickname).to eq("mama")

          authorization = Authorization.find_by(
            user: user,
            name: "msad_identity"
          )
          expect(authorization).not_to be_nil

          expect(authorization.metadata).to include(
            "name" => "Matti Mainio",
            "first_name" => "Matti",
            "last_name" => "Mainio",
            "nickname" => "mama",
            "groups" => %w(Managers HR),
            "date_of_birth" => "1985-07-15",
            "postal_code" => "00210",
            "phone" => "123456",
            "department" => "IT",
            "location" => "Helsinki",
            "employee_number" => "ABC123"
          )
        end

        # Decidim core would want to redirect to the verifications path on the
        # first sign in but we don't want that to happen as the user is already
        # authorized during the sign in process.
        it "redirects to the root path by default after a successful registration and first sign in" do
          omniauth_callback_get

          user = User.last

          expect(user.sign_in_count).to eq(1)
          expect(response).to redirect_to("/")
        end

        context "when the session has a pending redirect" do
          let(:after_sign_in_path) { "/processes" }

          before do
            # Do a mock request in order to create a session
            get "/"
            request.session["user_return_to"] = after_sign_in_path
          end

          it "redirects to the stored location by default after a successful registration and first sign in" do
            omniauth_callback_get(
              env: {
                "rack.session" => request.session,
                "rack.session.options" => request.session.options
              }
            )

            user = User.last

            expect(user.sign_in_count).to eq(1)
            expect(response).to redirect_to("/processes")
          end
        end

        context "when no email is returned from the IdP" do
          it "creates a new user record with auto-generated email" do
            omniauth_callback_get

            user = User.last

            expect(user.email).to match(/msad-[a-z0-9]{32}@1.lvh.me/)
          end
        end

        context "when email is returned from the IdP" do
          let(:saml_attributes) do
            {
              "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress" => ["matti.mainio@test.fi"]
            }
          end

          it "creates a new user record with the returned email" do
            omniauth_callback_get

            user = User.last

            expect(user.email).to eq("matti.mainio@test.fi")
          end
        end

        context "when email is returned from the IdP that matches existing user" do
          let(:saml_attributes) do
            {
              "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress" => [confirmed_user.email]
            }
          end

          it "hijacks the account for the returned email" do
            omniauth_callback_get

            authorization = Authorization.find_by(
              user: confirmed_user,
              name: "msad_identity"
            )
            expect(authorization).not_to be_nil
            expect(authorization.metadata).to include(
              "name" => "Matti Mainio",
              "first_name" => "Matti",
              "last_name" => "Mainio",
              "nickname" => "mama"
            )

            warden = request.env["warden"]
            current_user = warden.authenticate(scope: :user)
            expect(current_user).to eq(confirmed_user)
          end
        end

        context "when the user is already signed in" do
          before do
            sign_in confirmed_user
          end

          it "adds the authorization to the signed in user" do
            omniauth_callback_get

            expect(confirmed_user.name).not_to eq("Matti Mainio")
            expect(confirmed_user.nickname).not_to eq("matti_mainio")

            authorization = Authorization.find_by(
              user: confirmed_user,
              name: "msad_identity"
            )
            expect(authorization).not_to be_nil

            expect(authorization.metadata).to include(
              "name" => "Matti Mainio",
              "first_name" => "Matti",
              "last_name" => "Mainio",
              "nickname" => "mama",
              "groups" => %w(Managers HR),
              "date_of_birth" => "1985-07-15",
              "postal_code" => "00210",
              "phone" => "123456",
              "department" => "IT",
              "location" => "Helsinki",
              "employee_number" => "ABC123"
            )
          end

          it "redirects to the root path" do
            omniauth_callback_get

            expect(response).to redirect_to("/")
          end

          context "when the session has a pending redirect" do
            let(:after_sign_in_path) { "/processes" }

            before do
              # Do a mock request in order to create a session
              get "/"
              request.session["user_return_to"] = after_sign_in_path
            end

            it "redirects to the stored location" do
              omniauth_callback_get(
                env: {
                  "rack.session" => request.session,
                  "rack.session.options" => request.session.options
                }
              )

              expect(response).to redirect_to("/processes")
            end
          end
        end

        context "when the user is already signed in and authorized" do
          let!(:authorization) do
            signature = OmniauthRegistrationForm.create_signature(
              :msad,
              user_identifier
            )
            authorization = Decidim::Authorization.create(
              user: confirmed_user,
              name: "msad_identity",
              attributes: {
                unique_id: signature,
                metadata: {}
              }
            )
            authorization.save!
            authorization.grant!
            authorization
          end

          before do
            sign_in confirmed_user
          end

          it "updates the existing authorization" do
            omniauth_callback_get

            # Check that the user record was NOT updated
            expect(confirmed_user.name).not_to eq("Matti Mainio")
            expect(confirmed_user.nickname).not_to eq("matti_mainio")

            # Check that the authorization is the same one
            authorizations = Authorization.where(
              user: confirmed_user,
              name: "msad_identity"
            )
            expect(authorizations.count).to eq(1)
            expect(authorizations.first).to eq(authorization)

            # Check that the metadata was updated
            expect(authorizations.first.metadata).to include(
              "name" => "Matti Mainio",
              "first_name" => "Matti",
              "last_name" => "Mainio",
              "nickname" => "mama",
              "groups" => %w(Managers HR),
              "date_of_birth" => "1985-07-15",
              "postal_code" => "00210",
              "phone" => "123456",
              "department" => "IT",
              "location" => "Helsinki",
              "employee_number" => "ABC123"
            )
          end
        end

        context "when another user is already identified with the same identity" do
          let(:another_user) do
            create(:user, :confirmed, organization: organization)
          end

          before do
            another_user.identities.create!(
              organization: organization,
              provider: "msad",
              uid: user_identifier
            )

            # Sign in the confirmed user
            sign_in confirmed_user
          end

          it "prevents the authorization with correct error message" do
            omniauth_callback_get

            authorization = Authorization.find_by(
              user: confirmed_user,
              name: "msad_identity"
            )
            expect(authorization).to be_nil
            expect(response).to redirect_to("/users/auth/msad/spslo?RelayState=%2F")
            expect(flash[:alert]).to eq(
              "Another user has already been identified using this identity. Please sign out and sign in again directly using Active Directory."
            )
          end
        end

        context "when no SAML attributes are returned from the IdP" do
          let(:saml_attributes_base) { {} }
          let(:saml_attributes) { {} }

          it "prevents the authentication with correct error message" do
            omniauth_callback_get

            expect(User.count).to eq(0)
            expect(Authorization.count).to eq(0)
            expect(Identity.count).to eq(0)
            expect(flash[:alert]).to eq(
              "You cannot be authenticated through Active Directory."
            )
          end
        end

        context "when another user is already authorized with the same identity" do
          let(:another_user) do
            create(:user, :confirmed, organization: organization)
          end

          before do
            signature = OmniauthRegistrationForm.create_signature(
              :msad,
              user_identifier
            )
            authorization = Decidim::Authorization.create(
              user: another_user,
              name: "msad_identity",
              attributes: {
                unique_id: signature,
                metadata: {}
              }
            )
            authorization.save!
            authorization.grant!

            # Sign in the confirmed user
            sign_in confirmed_user
          end

          it "prevents the authorization with correct error message" do
            omniauth_callback_get

            authorization = Authorization.find_by(
              user: confirmed_user,
              name: "msad_identity"
            )
            expect(authorization).to be_nil
            expect(response).to redirect_to("/users/auth/msad/spslo?RelayState=%2F")
            expect(flash[:alert]).to eq(
              "Another user has already authorized themselves with the same identity."
            )
          end
        end

        context "with response handling being outside of the allowed timeframe" do
          let(:saml_response) do
            attrs = saml_attributes_base.merge(saml_attributes)
            resp_xml = generate_saml_response(attrs) do |doc|
              conditions_node = doc.root.at_xpath(
                "//saml2:Assertion//saml2:Conditions",
                saml2: "urn:oasis:names:tc:SAML:2.0:assertion"
              )
              conditions_node["NotBefore"] = "2010-08-10T13:03:46.695Z"
              conditions_node["NotOnOrAfter"] = "2010-08-10T13:03:46.695Z"
            end
            Base64.strict_encode64(resp_xml)
          end

          it "calls the failure endpoint" do
            omniauth_callback_get

            expect(User.last).to be_nil
            expect(response).to redirect_to("/users/sign_in")
            expect(flash[:alert]).to eq(
              "The authentication request was not handled within an allowed timeframe. Please try again."
            )
          end
        end

        context "with authentication session expired" do
          let(:saml_response) do
            attrs = saml_attributes_base.merge(saml_attributes)
            resp_xml = generate_saml_response(attrs) do |doc|
              authn_node = doc.root.at_xpath(
                "//saml2:Assertion//saml2:AuthnStatement",
                saml2: "urn:oasis:names:tc:SAML:2.0:assertion"
              )
              authn_node["SessionNotOnOrAfter"] = "2010-08-10T13:03:46.695Z"
            end
            Base64.strict_encode64(resp_xml)
          end

          it "calls the failure endpoint" do
            omniauth_callback_get

            expect(User.last).to be_nil
            expect(response).to redirect_to("/users/sign_in")
            expect(flash[:alert]).to eq(
              "Authentication session expired. Please try again."
            )
          end
        end

        context "with failed authentication" do
          let(:saml_response) do
            resp_xml = saml_response_from_file("failed_request.xml")
            Base64.strict_encode64(resp_xml)
          end

          it "calls the failure endpoint" do
            omniauth_callback_get

            expect(User.last).to be_nil
            expect(response).to redirect_to("/users/sign_in")
            expect(flash[:alert]).to eq(
              "Authentication failed or cancelled. Please try again."
            )
          end
        end

        def omniauth_callback_get(env: nil)
          request_args = { params: { SAMLResponse: saml_response } }
          request_args[:env] = env if env

          # Call the endpoint with the SAML response
          get "/users/auth/msad/callback", **request_args
        end
      end

      def generate_saml_response(attributes = {})
        saml_response_from_file("saml_response_blank.xml", sign: true) do |doc|
          root_element = doc.root
          statements_node = root_element.at_xpath(
            "//saml2:Assertion//saml2:AttributeStatement",
            saml2: "urn:oasis:names:tc:SAML:2.0:assertion"
          )

          if attributes.blank?
            statements_node.remove
          else
            attributes.each do |name, value|
              attr_element = Nokogiri::XML::Node.new "Attribute", doc
              attr_element["Name"] = name
              Array(value).each do |item|
                next if item.blank?

                attr_element.add_child("<AttributeValue>#{item}</AttributeValue>")
              end

              statements_node.add_child(attr_element)
            end
          end

          yield doc if block_given?
        end
      end

      def saml_response_from_file(file, sign: false)
        filepath = file_fixture(file)
        file_io = IO.read(filepath)
        doc = Nokogiri::XML::Document.parse(file_io)

        yield doc if block_given?

        doc = sign_xml(doc) if sign

        doc.to_s
      end

      def sign_xml(xml_doc)
        cert = OpenSSL::X509::Certificate.new(File.read(file_fixture("idp.crt")))
        pkey = OpenSSL::PKey::RSA.new(File.read(file_fixture("idp.key")))

        # doc = XMLSecurity::Document.new(xml_string)
        # doc = Nokogiri::XML::Document.parse(xml_string)
        assertion_node = xml_doc.root.at_xpath(
          "//saml2:Assertion",
          saml2: "urn:oasis:names:tc:SAML:2.0:assertion"
        )

        # The assertion node needs to be canonicalized in order for the digests
        # to match because the canonicalization handles specific elements in the
        # XML a bit differently which causes different XML output on some nodes
        # such as the `<SubjectConfirmationData>` node.
        noko = Nokogiri::XML(assertion_node.to_s) do |config|
          config.options = XMLSecurity::BaseDocument::NOKOGIRI_OPTIONS
        end
        assertion_canon = noko.canonicalize(
          Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0,
          XMLSecurity::Document::INC_PREFIX_LIST.split(" ")
        )

        assertion_doc = XMLSecurity::Document.new(assertion_canon)
        assertion_doc.sign_document(
          pkey,
          cert,
          XMLSecurity::Document::RSA_SHA256,
          XMLSecurity::Document::SHA256
        )
        assertion = Nokogiri::XML::Document.parse(assertion_doc.to_s)
        signature = assertion.root.at_xpath(
          "//ds:Signature",
          ds: "http://www.w3.org/2000/09/xmldsig#"
        )

        # Remove blanks from the signature according to:
        # https://stackoverflow.com/a/35806327
        #
        # This is needed in order for the signature validation to succeed.
        # Otherwise it would fail because the signature is validated against the
        # signature node without any intendation or blanks between the XML tags.
        # We need a separate document for this in order for the blank removal to
        # work correctly.
        signature_doc = Nokogiri::XML::Document.parse(signature.to_s)
        signature_doc.search("//text()").each do |text_node|
          text_node.content = "" if text_node.content.strip.empty?
        end
        signature = signature_doc.root.at_xpath(
          "//ds:Signature",
          ds: "http://www.w3.org/2000/09/xmldsig#"
        )

        # Inject the signature to the correct place in the document
        issuer = xml_doc.root.at_xpath(
          "//saml2:Assertion//saml2:Issuer",
          saml2: "urn:oasis:names:tc:SAML:2.0:assertion"
        )
        issuer.after(signature.to_s)

        xml_doc
      end
    end
  end
end
