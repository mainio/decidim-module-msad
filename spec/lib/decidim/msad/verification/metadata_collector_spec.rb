# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Msad
    module Verification
      describe MetadataCollector do
        subject { described_class.new(tenant, OneLogin::RubySaml::Attributes.new(saml_attributes)) }

        let(:tenant) { Decidim::Msad.tenants.first }
        let(:oauth_provider) { "provider" }
        let(:oauth_uid) { "uid" }
        let(:oauth_email) { nil }
        let(:oauth_first_name) { "Marja" }
        let(:oauth_last_name) { "Mainio" }
        let(:oauth_name) { "Marja Mainio" }
        let(:oauth_nickname) { "mmainio" }

        let(:saml_attributes) do
          {
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name" => ["Marja Mainio"],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress" => ["user@example.org"],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname" => ["Marja"],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname" => ["Mainio"],
            "http://schemas.microsoft.com/identity/claims/displayname" => ["mmainio"],
            "http://schemas.microsoft.com/ws/2008/06/identity/claims/groups" => %w(Managers HR),
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/dateofbirth" => ["1985-07-15"],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/postalcode" => ["00210"],
            "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/mobilephone" => ["123456"],
            "Department" => ["IT"],
            "Location" => ["Helsinki"],
            "EmployeeID" => ["ABC123"]
          }
        end

        context "when the module has not been configured to collect the metadata" do
          before do
            tenant.metadata_attributes = {}
          end

          it "does not collect any metadata" do
            expect(subject.metadata).to be_nil
          end
        end

        context "when the module has been cofigured to collect the metadata" do
          before do
            tenant.metadata_attributes = {
              name: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
              email: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
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
          end

          after do
            tenant.metadata_attributes = {}
          end

          it "collects the correct metadata" do
            expect(subject.metadata).to include(
              name: "Marja Mainio",
              email: "user@example.org",
              first_name: "Marja",
              last_name: "Mainio",
              nickname: "mmainio",
              groups: %w(Managers HR),
              date_of_birth: "1985-07-15",
              postal_code: "00210",
              phone: "123456",
              department: "IT",
              location: "Helsinki",
              employee_number: "ABC123"
            )
          end
        end
      end
    end
  end
end
