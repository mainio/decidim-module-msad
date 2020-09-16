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
          next unless Decidim::Msad.configured?

          # We cannot use the name `:msad` for the verification workflow
          # because otherwise the route namespace (decidim_msad) would
          # conflict with the main engine controlling the authentication flows.
          # The main problem that this would bring is that the root path for
          # this engine would not be found.
          Decidim::Verifications.register_workflow(:msad_identity) do |workflow|
            workflow.engine = Decidim::Msad::Verification::Engine

            Decidim::Msad::Verification::Manager.configure_workflow(workflow)
          end
        end

        def load_seed
          # Enable the `:msad_identity` authorization
          org = Decidim::Organization.first
          org.available_authorizations << :msad_identity
          org.save!
        end
      end
    end
  end
end
