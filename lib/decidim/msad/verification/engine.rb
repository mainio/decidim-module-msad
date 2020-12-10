# frozen_string_literal: true

module Decidim
  module Msad
    module Verification
      # This is an engine that performs user authorization.
      class Engine < ::Rails::Engine
        isolate_namespace Decidim::Msad::Verification

        paths["db/migrate"] = nil
        paths["lib/tasks"] = nil

        routes do
          resource :authorizations, only: [:new], as: :authorization

          root to: "authorizations#new"
        end

        initializer "decidim_msad.verification_workflow", after: :load_config_initializers do
          Decidim::Msad.tenants.each do |tenant|
            # We cannot use the same name as the tenant for the verification
            # workflow because otherwise the route namespace (e.g.
            # "decidim_msad") would conflict with the main engine controlling
            # the authentication flows. The main problem that this would bring
            # is that the root path for this engine would not be found.
            Decidim::Verifications.register_workflow("#{tenant.name}_identity".to_sym) do |workflow|
              workflow.engine = Decidim::Msad::Verification::Engine

              tenant.workflow_configurator.call(workflow)
            end
          end
        end

        def load_seed
          Decidim::Msad.tenants.each do |tenant|
            # Enable the authorizations for each tenant
            org = Decidim::Organization.first
            org.available_authorizations << "#{tenant.name}_identity".to_sym
            org.save!
          end
        end
      end
    end
  end
end
