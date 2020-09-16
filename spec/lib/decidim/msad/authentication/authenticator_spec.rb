# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Msad
    module Authentication
      describe Authenticator do
        subject { described_class.new(organization, oauth_hash) }

        let(:organization) { create(:organization) }
        let(:oauth_hash) do
          {
            provider: oauth_provider,
            uid: oauth_uid,
            info: {
              email: oauth_email,
              name: oauth_name,
              first_name: oauth_first_name,
              last_name: oauth_last_name,
              nickname: oauth_nickname,
              image: oauth_image
            },
            extra: {
              raw_info: OneLogin::RubySaml::Attributes.new(saml_attributes)
            }
          }
        end
        let(:oauth_provider) { "provider" }
        let(:oauth_uid) { "uid" }
        let(:oauth_email) { nil }
        let(:oauth_first_name) { "Marja" }
        let(:oauth_last_name) { "Mainio" }
        let(:oauth_name) { "Marja Mainio" }
        let(:oauth_nickname) { "mmainio" }
        let(:oauth_image) { nil }
        let(:saml_attributes) do
          {
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name" => [oauth_name],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress" => [oauth_email],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname" => [oauth_first_name],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname" => [oauth_last_name],
            "http://schemas.microsoft.com/identity/claims/displayname" => [oauth_nickname]
          }.delete_if { |_k, v| v.nil? }
        end

        describe "#verified_email" do
          context "when email is available in the OAuth info" do
            let(:oauth_email) { "user@example.org" }

            it "returns the email from SAML attributes" do
              expect(subject.verified_email).to eq("user@example.org")
            end
          end

          context "when email is not available in the SAML attributes" do
            it "auto-creates the email using the known pattern" do
              expect(subject.verified_email).to match(/msad-[a-z0-9]{32}@1.lvh.me/)
            end

            context "and auto_email_domain is not defined" do
              before do
                allow(Decidim::Msad).to receive(:auto_email_domain).and_return(nil)
              end

              it "auto-creates the email using the known pattern" do
                expect(subject.verified_email).to match(/msad-[a-z0-9]{32}@#{organization.host}/)
              end
            end
          end
        end

        describe "#user_params_from_oauth_hash" do
          it "returns the expected hash" do
            signature = ::Decidim::OmniauthRegistrationForm.create_signature(
              oauth_provider,
              oauth_uid
            )

            expect(subject.user_params_from_oauth_hash).to include(
              provider: oauth_provider,
              uid: oauth_uid,
              name: oauth_name,
              nickname: oauth_nickname,
              oauth_signature: signature,
              avatar_url: nil,
              raw_data: oauth_hash
            )
          end

          context "when oauth data is empty" do
            let(:oauth_hash) { {} }

            it "returns nil" do
              expect(subject.user_params_from_oauth_hash).to be_nil
            end
          end

          context "when user identifier is blank" do
            let(:oauth_uid) { nil }

            it "returns nil" do
              expect(subject.user_params_from_oauth_hash).to be_nil
            end
          end

          context "when nickname does not exist" do
            let(:oauth_nickname) { nil }

            it "uses name as the nickname" do
              expect(subject.user_params_from_oauth_hash).to include(
                name: oauth_name,
                nickname: oauth_name
              )
            end
          end
        end

        describe "#validate!" do
          it "returns true for valid authentication data" do
            expect(subject.validate!).to be(true)
          end

          context "when no SAML attributes are available" do
            let(:saml_attributes) { {} }

            it "raises a ValidationError" do
              expect do
                subject.validate!
              end.to raise_error(
                Decidim::Msad::Authentication::ValidationError,
                "No SAML data provided"
              )
            end
          end

          context "when all SAML attributes values are blank" do
            let(:saml_attributes) do
              {
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name" => [],
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress" => [],
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname" => [],
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname" => [],
                "http://schemas.microsoft.com/identity/claims/displayname" => nil
              }
            end

            it "raises a ValidationError" do
              expect do
                subject.validate!
              end.to raise_error(
                Decidim::Msad::Authentication::ValidationError,
                "Invalid SAML data"
              )
            end
          end

          context "when there is no person identifier" do
            let(:oauth_uid) { nil }

            it "raises a ValidationError" do
              expect do
                subject.validate!
              end.to raise_error(
                Decidim::Msad::Authentication::ValidationError,
                "Invalid person dentifier"
              )
            end
          end
        end

        describe "#identify_user!" do
          let(:user) { create(:user, :confirmed, organization: organization) }

          it "creates a new identity for the user" do
            id = subject.identify_user!(user)

            expect(Decidim::Identity.count).to eq(1)
            expect(Decidim::Identity.last.id).to eq(id.id)
            expect(id.organization.id).to eq(organization.id)
            expect(id.user.id).to eq(user.id)
            expect(id.provider).to eq(oauth_provider)
            expect(id.uid).to eq(oauth_uid)
          end

          context "when an identity already exists" do
            let!(:identity) do
              user.identities.create!(
                organization: organization,
                provider: oauth_provider,
                uid: oauth_uid
              )
            end

            it "returns the same identity" do
              expect(subject.identify_user!(user).id).to eq(identity.id)
            end
          end

          context "when a matching identity already exists for another user" do
            let(:another_user) { create(:user, :confirmed, organization: organization) }

            before do
              another_user.identities.create!(
                organization: organization,
                provider: oauth_provider,
                uid: oauth_uid
              )
            end

            it "raises an IdentityBoundToOtherUserError" do
              expect do
                subject.identify_user!(user)
              end.to raise_error(
                Decidim::Msad::Authentication::IdentityBoundToOtherUserError
              )
            end
          end
        end

        describe "#authorize_user!" do
          let(:user) { create(:user, :confirmed, organization: organization) }
          let(:signature) do
            ::Decidim::OmniauthRegistrationForm.create_signature(
              oauth_provider,
              oauth_uid
            )
          end

          it "creates a new authorization for the user" do
            auth = subject.authorize_user!(user)

            expect(Decidim::Authorization.count).to eq(1)
            expect(Decidim::Authorization.last.id).to eq(auth.id)
            expect(auth.user.id).to eq(user.id)
            expect(auth.unique_id).to eq(signature)
            expect(auth.metadata).to be(nil)
          end

          context "when the metadata collector has been configured to collect attributes" do
            let(:saml_attributes) do
              {
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name" => [oauth_name],
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress" => [oauth_email],
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname" => [oauth_first_name],
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname" => [oauth_last_name],
                "http://schemas.microsoft.com/ws/2008/06/identity/claims/groups" => %w(Managers HR),
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/dateofbirth" => ["1985-07-15"],
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/postalcode" => ["00210"],
                "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/mobilephone" => ["123456"],
                "Department" => ["IT"],
                "Location" => ["Helsinki"],
                "EmployeeID" => ["ABC123"]
              }
            end

            before do
              Decidim::Msad.metadata_attributes = {
                department: "Department",
                location: "Location",
                phone: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/mobilephone",
                postal_code: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/postalcode",
                employee_number: "EmployeeID",
                date_of_birth: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/dateofbirth",
                groups: { name: "http://schemas.microsoft.com/ws/2008/06/identity/claims/groups", type: :multi }
              }
            end

            after do
              Decidim::Msad.metadata_attributes = {}
            end

            it "creates a new authorization for the user with the correct metadata" do
              auth = subject.authorize_user!(user)

              expect(Decidim::Authorization.count).to eq(1)
              expect(Decidim::Authorization.last.id).to eq(auth.id)
              expect(auth.user.id).to eq(user.id)
              expect(auth.unique_id).to eq(signature)
              expect(auth.metadata).to include(
                "department" => "IT",
                "location" => "Helsinki",
                "phone" => "123456",
                "postal_code" => "00210",
                "employee_number" => "ABC123",
                "date_of_birth" => "1985-07-15",
                "groups" => %w(Managers HR)
              )
            end
          end

          context "when an authorization already exists" do
            let!(:authorization) do
              Decidim::Authorization.create!(
                name: "msad_identity",
                user: user,
                unique_id: signature
              )
            end

            it "returns the existing authorization and updates it" do
              auth = subject.authorize_user!(user)

              expect(auth.id).to eq(authorization.id)
              expect(auth.metadata).to be(nil)
            end
          end

          context "when a matching authorization already exists for another user" do
            let(:another_user) { create(:user, :confirmed, organization: organization) }

            before do
              Decidim::Authorization.create!(
                name: "msad_identity",
                user: another_user,
                unique_id: signature
              )
            end

            it "raises an IdentityBoundToOtherUserError" do
              expect do
                subject.authorize_user!(user)
              end.to raise_error(
                Decidim::Msad::Authentication::AuthorizationBoundToOtherUserError
              )
            end
          end
        end
      end
    end
  end
end
