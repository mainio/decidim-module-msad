# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Msad
    describe Engine do
      # Some of the tests may be causing the Devise OmniAuth strategies to be
      # reconfigured in which case the strategy option information is lost in
      # the Devise configurations. In case the strategy is lost, re-initialize
      # it manually. Normally this is done when the application's middleware
      # stack is loaded.
      after do
        Decidim::Msad.tenants do |tenant|
          name = tenant.name.to_sym
          next if ::Devise.omniauth_configs[name].strategy

          ::OmniAuth::Strategies::MSAD.new(
            Rails.application,
            tenant.omniauth_settings
          ) do |strategy|
            ::Devise.omniauth_configs[name].strategy = strategy
          end
        end
      end

      it "mounts the routes to the core engine" do
        routes = double
        allow(Decidim::Core::Engine).to receive(:routes).and_return(routes)
        expect(Decidim::Core::Engine).to receive(:routes)
        expect(routes).to receive(:prepend) do |&block|
          context = double
          expect(context).to receive(:mount).with(described_class => "/")
          context.instance_eval(&block)
        end

        run_initializer("decidim_msad.mount_routes")
      end

      it "adds the correct sign out routes to the core engine" do
        %w(DELETE POST).each do |method|
          expect(
            Decidim::Core::Engine.routes.recognize_path(
              "/users/sign_out",
              method: method
            )
          ).to eq(
            controller: "decidim/msad/sessions",
            action: "destroy"
          )
        end

        expect(
          Decidim::Core::Engine.routes.recognize_path(
            "/users/slo_callback",
            method: "GET"
          )
        ).to eq(
          controller: "decidim/msad/sessions",
          action: "slo_callback"
        )
      end

      it "configures the MSAD omniauth strategy for Devise" do
        expect(::Devise).to receive(:setup) do |&block|
          config = double
          expect(config).to receive(:omniauth).with(
            :msad,
            name: "msad",
            strategy_class: OmniAuth::Strategies::MSAD,
            idp_metadata_file: nil,
            idp_metadata_url: "https://login.microsoftonline.com/987f6543-1e0d-12a3-45b6-789012c345de/federationmetadata/2007-06/federationmetadata.xml",
            sp_entity_id: "http://1.lvh.me/users/auth/msad/metadata",
            sp_name_qualifier: "http://1.lvh.me/users/auth/msad/metadata",
            sp_metadata: [],
            assertion_consumer_service_url: "https://localhost:3000/users/auth/msad/callback",
            certificate: nil,
            private_key: nil,
            single_logout_service_url: "https://localhost:3000/users/auth/msad/slo",
            idp_slo_session_destroy: instance_of(Proc)
          )
          block.call(config)
        end
        expect(::Devise).to receive(:setup) do |&block|
          config = double
          expect(config).to receive(:omniauth).with(
            :other,
            name: "other",
            strategy_class: OmniAuth::Strategies::MSAD,
            idp_metadata_file: nil,
            idp_metadata_url: "https://login.microsoftonline.com/876f5432-1e0d-12a3-45b6-789012c345de/federationmetadata/2007-06/federationmetadata.xml",
            sp_entity_id: "http://2.lvh.me/users/auth/other/metadata",
            sp_name_qualifier: "http://2.lvh.me/users/auth/other/metadata",
            sp_metadata: [],
            assertion_consumer_service_url: "https://localhost:3000/users/auth/other/callback",
            certificate: nil,
            private_key: nil,
            single_logout_service_url: "https://localhost:3000/users/auth/other/slo",
            idp_slo_session_destroy: instance_of(Proc)
          )
          block.call(config)
        end

        allow(Decidim::Msad).to receive(:initialized?).and_return(false)
        run_initializer("decidim_msad.setup")
      end

      it "configures the OmniAuth failure app" do
        expect(OmniAuth.config).to receive(:on_failure=) do |proc|
          env = double
          action = double
          expect(env).to receive(:[]).with("PATH_INFO").twice.and_return(
            "/users/auth/msad"
          )
          expect(env).to receive(:[]=).with("devise.mapping", ::Devise.mappings[:user])
          allow(Decidim::Msad::OmniauthCallbacksController).to receive(
            :action
          ).with(:failure).and_return(action)
          expect(Decidim::Msad::OmniauthCallbacksController).to receive(:action)
          expect(action).to receive(:call).with(env)

          proc.call(env)
        end
        expect(OmniAuth.config).to receive(:on_failure=) do |proc|
          env = double
          action = double
          expect(env).to receive(:[]).with("PATH_INFO").twice.and_return(
            "/users/auth/other"
          )
          expect(env).to receive(:[]=).with("devise.mapping", ::Devise.mappings[:user])
          allow(Decidim::Msad::OmniauthCallbacksController).to receive(
            :action
          ).with(:failure).and_return(action)
          expect(Decidim::Msad::OmniauthCallbacksController).to receive(:action)
          expect(action).to receive(:call).with(env)

          proc.call(env)
        end

        allow(Decidim::Msad).to receive(:initialized?).and_return(false)
        run_initializer("decidim_msad.setup")
      end

      it "falls back on the default OmniAuth failure app" do
        failure_app = double

        expect(OmniAuth.config).to receive(:on_failure).twice.and_return(failure_app)
        expect(OmniAuth.config).to receive(:on_failure=).twice do |proc|
          env = double
          expect(env).to receive(:[]).with("PATH_INFO").twice.and_return(
            "/something/else"
          )
          expect(failure_app).to receive(:call).with(env)

          proc.call(env)
        end

        allow(Decidim::Msad).to receive(:initialized?).and_return(false)
        run_initializer("decidim_msad.setup")
      end

      it "adds the mail interceptor" do
        expect(ActionMailer::Base).to receive(:register_interceptor).with(
          Decidim::Msad::MailInterceptors::GeneratedRecipientsInterceptor
        )

        run_initializer("decidim_msad.mail_interceptors")
      end

      def run_initializer(initializer_name)
        config = described_class.initializers.find do |i|
          i.name == initializer_name
        end
        config.run
      end
    end
  end
end
