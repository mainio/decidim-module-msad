# frozen_string_literal: true

module Decidim
  module Msad
    module Verification
      class MetadataCollector
        def initialize(tenant, saml_attributes)
          @tenant = tenant
          @saml_attributes = saml_attributes
        end

        def metadata
          return nil unless tenant.metadata_attributes.is_a?(Hash)
          return nil if tenant.metadata_attributes.blank?

          collect.delete_if { |_k, v| v.nil? }
        end

        protected

        attr_reader :tenant, :saml_attributes

        def collect
          tenant.metadata_attributes.to_h do |key, defs|
            value = case defs
                    when Hash
                      saml_attributes.public_send(defs[:type], defs[:name])
                    when String
                      saml_attributes.single(defs)
                    end

            [key, value]
          end
        end
      end
    end
  end
end
