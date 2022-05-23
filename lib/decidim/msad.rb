# frozen_string_literal: true

require "omniauth"
require "omniauth/strategies/msad"

# Make sure the omniauth methods work after OmniAuth 2.0+
require "omniauth/rails_csrf_protection"

require_relative "msad/version"
require_relative "msad/engine"
require_relative "msad/authentication"
require_relative "msad/verification"
require_relative "msad/mail_interceptors"

module Decidim
  module Msad
    autoload :Tenant, "decidim/msad/tenant"

    class << self
      def tenants
        @tenants ||= []
      end

      def test!
        @test = true
      end

      def configure(&block)
        tenant = Decidim::Msad::Tenant.new(&block)
        tenants.each do |existing|
          if tenant.name == existing.name
            raise(
              TenantNameTooSimilar,
              "Please define an individual name for the MSAD tenant. The name \"#{tenant.name}\" is already in use."
            )
          end

          match = tenant.name =~ /^#{existing.name}/
          match ||= existing.name =~ /^#{tenant.name}/
          next unless match

          raise(
            TenantNameTooSimilar,
            "MSAD tenant name \"#{tenant.name}\" is too similar with: #{existing.name}"
          )
        end

        tenants << tenant
      end

      def setup!
        raise "MSAD module is already initialized!" if initialized?

        @initialized = true
        tenants.each(&:setup!)
      end

      private

      def initialized?
        @initialized
      end
    end

    class TenantNameTooSimilar < StandardError; end
    class InvalidTenantName < StandardError; end
  end
end
