# frozen_string_literal: true

require "spec_helper"

module Decidim
  describe Msad do
    describe ".tenants" do
      it "returns the configured tenants" do
        expect(described_class.tenants.count).to eq(2)
        expect(described_class.tenants.map(&:name)).to match_array(%w(msad other))
      end

      context "when there are no tenants" do
        before do
          described_class.tenants.clear
        end

        after do
          # Reset the tenant settings to defaults
          Decidim::Msad::Test::Runtime.initialize
        end

        it "returns an empty array" do
          expect(described_class.tenants).to eq([])
        end
      end
    end

    describe ".configure" do
      after do
        # Reset the tenant settings to defaults
        described_class.tenants.clear
        Decidim::Msad::Test::Runtime.initialize
      end

      it "configures a new tenant" do
        described_class.configure do |config|
          config.name = "third"
        end

        expect(described_class.tenants.count).to eq(3)
        expect(described_class.tenants.map(&:name)).to match_array(%w(msad other third))
      end

      context "when the new name matches with existing names" do
        it "raises a TenantNameTooSimilar" do
          described_class.test!

          expect do
            described_class.configure do |config|
              config.name = "msad"
            end
          end.to raise_error(Decidim::Msad::TenantNameTooSimilar)
        end
      end

      context "when the new name is too similar with existing names" do
        it "raises a TenantNameTooSimilar" do
          described_class.test!

          expect do
            described_class.configure do |config|
              # Should match with existing "msad"
              config.name = "msad_other"
            end
          end.to raise_error(Decidim::Msad::TenantNameTooSimilar)
        end
      end

      context "when one of the existing names is too similar with the new name" do
        it "raises a TenantNameTooSimilar" do
          described_class.test!

          expect do
            described_class.configure do |config|
              config.name = "oth"
            end
          end.to raise_error(Decidim::Msad::TenantNameTooSimilar)
        end
      end
    end

    describe ".setup!" do
      it "calls the setup method for all tenants" do
        allow(described_class).to receive(:initialized?).and_return(false)
        expect(described_class.tenants).to all(receive(:setup!))
        described_class.setup!
      end
    end
  end
end
