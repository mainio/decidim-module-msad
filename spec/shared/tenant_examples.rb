# frozen_string_literal: true

shared_examples "an MSAD tenant" do |name|
  subject do
    described_class.new do |config|
      config.name = name
    end
  end

  describe "#setup!" do
    let(:metadata_file) { double }
    let(:metadata_url) { double }

    it "configures the routes" do
      expect(Decidim::Msad::Engine).to receive(:routes)
      subject.setup!
    end

    it "configures the MSAD omniauth strategy for Devise" do
      subject.idp_metadata_file = metadata_file
      subject.idp_metadata_url = metadata_url

      expect(::Devise).to receive(:setup) do |&block|
        config = double
        expect(config).to receive(:omniauth).with(
          name.to_sym,
          {
            name: name,
            strategy_class: OmniAuth::Strategies::MSAD,
            idp_metadata_file: metadata_file,
            idp_metadata_url: metadata_url,
            sp_entity_id: "https://localhost:3000/users/auth/#{name}/metadata",
            sp_name_qualifier: "https://localhost:3000/users/auth/#{name}/metadata",
            sp_metadata: [],
            assertion_consumer_service_url: "https://localhost:3000/users/auth/#{name}/callback",
            certificate: nil,
            private_key: nil,
            single_logout_service_url: "https://localhost:3000/users/auth/#{name}/slo",
            idp_slo_session_destroy: instance_of(Proc)
          }
        )
        block.call(config)
      end

      subject.setup!
    end
  end

  describe "#setup_routes!" do
    it "adds the correct callback and passthru routes to the core engine" do
      subject.setup_routes!

      %w(GET POST).each do |method|
        expect(
          Decidim::Core::Engine.routes.recognize_path(
            "/users/auth/#{name}",
            method: method
          )
        ).to eq(
          controller: "decidim/msad/omniauth_callbacks",
          action: "passthru"
        )
        expect(
          Decidim::Core::Engine.routes.recognize_path(
            "/users/auth/#{name}/callback",
            method: method
          )
        ).to eq(
          controller: "decidim/msad/omniauth_callbacks",
          action: "msad"
        )
      end
    end

    it "adds the correct sign out routes to the core engine" do
      %w(GET POST).each do |method|
        expect(
          Decidim::Core::Engine.routes.recognize_path(
            "/users/auth/msad/slo",
            method: method
          )
        ).to eq(
          controller: "decidim/msad/sessions",
          action: "slo"
        )
        expect(
          Decidim::Core::Engine.routes.recognize_path(
            "/users/auth/msad/spslo",
            method: method
          )
        ).to eq(
          controller: "decidim/msad/sessions",
          action: "spslo"
        )
      end
    end
  end

  context "with mocked configuration" do
    describe "#sp_entity_id" do
      it "returns the correct path by default" do
        allow(Rails.application.config.action_controller).to receive(:default_url_options).and_return(
          host: "www.example.org",
          protocol: "https"
        )

        expect(subject.sp_entity_id).to eq(
          "https://www.example.org/users/auth/#{name}/metadata"
        )
      end

      context "when configured through module configuration" do
        it "returns what is set by the module configuration" do
          expect(subject.sp_entity_id).to eq("https://localhost:3000/users/auth/#{name}/metadata")
        end
      end
    end

    describe "#certificate" do
      it "returns the certificate file content when configured with a file" do
        file = double
        contents = double
        subject.certificate_file = file
        allow(File).to receive(:read).with(file).and_return(contents)

        expect(subject.certificate).to eq(contents)
      end

      context "when configured through module configuration" do
        let(:certificate) { double }

        it "returns what is set by the module configuration" do
          subject.config.certificate = certificate
          expect(subject.certificate).to eq(certificate)
        end
      end
    end

    describe "#private_key" do
      it "returns the private key file content when configured with a file" do
        file = double
        contents = double
        subject.private_key_file = file
        allow(File).to receive(:read).with(file).and_return(contents)

        expect(subject.private_key).to eq(contents)
      end

      context "when configured through module configuration" do
        let(:private_key) { double }

        it "returns what is set by the module configuration" do
          subject.config.private_key = private_key
          expect(subject.private_key).to eq(private_key)
        end
      end
    end

    describe "#omniauth_settings" do
      let(:idp_metadata_file) { double }
      let(:idp_metadata_url) { double }
      let(:sp_entity_id) { double }
      let(:sp_metadata) { double }
      let(:certificate) { double }
      let(:private_key) { double }
      let(:idp_slo_session_destroy) { double }
      let(:extra) { { extra1: "abc", extra2: 123 } }

      it "returns the expected omniauth configuration hash" do
        subject.config.idp_metadata_file = idp_metadata_file
        subject.config.idp_metadata_url = idp_metadata_url
        subject.config.sp_entity_id = sp_entity_id
        subject.config.sp_metadata = sp_metadata
        subject.config.certificate = certificate
        subject.config.private_key = private_key
        subject.config.idp_slo_session_destroy = idp_slo_session_destroy
        subject.config.extra = extra

        expect(subject.omniauth_settings).to include(
          name: name,
          strategy_class: OmniAuth::Strategies::MSAD,
          idp_metadata_file: idp_metadata_file,
          idp_metadata_url: idp_metadata_url,
          sp_entity_id: sp_entity_id,
          sp_name_qualifier: sp_entity_id,
          sp_metadata: sp_metadata,
          certificate: certificate,
          private_key: private_key,
          idp_slo_session_destroy: idp_slo_session_destroy,
          assertion_consumer_service_url: "https://localhost:3000/users/auth/#{name}/callback",
          single_logout_service_url: "https://localhost:3000/users/auth/#{name}/slo",
          extra1: "abc",
          extra2: 123
        )
      end
    end

    describe "#application_host" do
      let(:rails_config) { double }
      let(:controller_config) { double }
      let(:mailer_config) { double }

      let(:controller_defaults) { nil }
      let(:mailer_defaults) { nil }

      before do
        allow(Rails.application).to receive(:config).and_return(rails_config)
        allow(rails_config).to receive(:action_controller).and_return(controller_config)
        allow(rails_config).to receive(:action_mailer).and_return(mailer_config)
        allow(controller_config).to receive(:default_url_options).and_return(controller_defaults)
        allow(mailer_config).to receive(:default_url_options).and_return(mailer_defaults)
      end

      it "returns the development host by default" do
        expect(subject.application_host).to eq("https://localhost:3000")
      end

      context "with controller config without a host" do
        let(:controller_defaults) { { port: 8000 } }

        it "returns the default development host without applying the configured port" do
          expect(subject.application_host).to eq("https://localhost:3000")
        end

        context "and mailer configuration having a host" do
          let(:mailer_defaults) { { host: "www.example.org" } }

          it "returns the mailer config host" do
            expect(subject.application_host).to eq("https://www.example.org")
          end
        end

        context "and mailer configuration having a host and a port" do
          let(:mailer_defaults) { { host: "www.example.org", port: 4443 } }

          it "returns the mailer config host and port" do
            expect(subject.application_host).to eq("https://www.example.org:4443")
          end
        end
      end

      context "with controller config having a host" do
        let(:controller_defaults) { { host: "www.example.org" } }
        let(:mailer_defaults) { { host: "www.mailer.org", port: 4443 } }

        it "returns the controller config host" do
          expect(subject.application_host).to eq("https://www.example.org")
        end
      end

      context "with controller config having a host and a port" do
        let(:controller_defaults) { { host: "www.example.org", port: 8080 } }
        let(:mailer_defaults) { { host: "www.mailer.org", port: 4443 } }

        it "returns the controller config host and port" do
          expect(subject.application_host).to eq("https://www.example.org:8080")
        end

        context "when the port is 80" do
          let(:controller_defaults) { { host: "www.example.org", port: 80 } }

          it "does not append it to the host" do
            expect(subject.application_host).to eq("http://www.example.org")
          end
        end

        context "when the port is 443" do
          let(:controller_defaults) { { host: "www.example.org", port: 443 } }

          it "does not append it to the host" do
            expect(subject.application_host).to eq("https://www.example.org")
          end
        end
      end

      context "with mailer config having a host" do
        let(:mailer_defaults) { { host: "www.example.org" } }

        it "returns the mailer config host" do
          expect(subject.application_host).to eq("https://www.example.org")
        end
      end

      context "with mailer config having a host and a port" do
        let(:mailer_defaults) { { host: "www.example.org", port: 8080 } }

        it "returns the mailer config host and port" do
          expect(subject.application_host).to eq("https://www.example.org:8080")
        end

        context "when the port is 80" do
          let(:mailer_defaults) { { host: "www.example.org", port: 80 } }

          it "does not append it to the host" do
            expect(subject.application_host).to eq("http://www.example.org")
          end
        end

        context "when the port is 443" do
          let(:mailer_defaults) { { host: "www.example.org", port: 443 } }

          it "does not append it to the host" do
            expect(subject.application_host).to eq("https://www.example.org")
          end
        end
      end
    end
  end
end
