# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "generators/decidim/msad/install_generator"

module Decidim
  module Msad
    module Generators
      describe InstallGenerator do
        let(:options) { {} }

        before { allow(subject).to receive(:options).and_return(options) }

        describe "#copy_initializer" do
          it "copies the initializer file" do
            expect(subject).to receive(:copy_file).with(
              "msad_initializer.rb",
              "config/initializers/msad.rb"
            )
            subject.copy_initializer
          end

          context "with the test_initializer option set to true" do
            let(:options) { { test_initializer: true } }

            it "copies the test initializer file" do
              expect(subject).to receive(:copy_file).with(
                "msad_initializer_test.rb",
                "config/initializers/msad.rb"
              )
              subject.copy_initializer
            end
          end
        end

        describe "#enable_authentication" do
          let(:secrets_yml_template) do
            yml = "default: &default\n"
            yml += "  omniauth:\n"
            yml += "    facebook:\n"
            yml += "      enabled: false\n"
            yml += "      app_id: 1234\n"
            yml += "      app_secret: 4567\n"
            yml += "%MSAD_INJECTION_DEFAULT%"
            yml += "  geocoder:\n"
            yml += "    here_app_id: 1234\n"
            yml += "    here_app_code: 1234\n"
            yml += "\n"
            yml += "development:\n"
            yml += "  <<: *default\n"
            yml += "  secret_key_base: aaabbb\n"
            yml += "  omniauth:\n"
            yml += "    developer:\n"
            yml += "      enabled: true\n"
            yml += "      icon: phone\n"
            yml += "%MSAD_INJECTION_DEVELOPMENT%"
            yml += "\n"
            yml += "test:\n"
            yml += "  <<: *default\n"
            yml += "  secret_key_base: cccddd\n"
            yml += "\n"

            yml
          end

          let(:secrets_yml) do
            secrets_yml_template.gsub(
              /%MSAD_INJECTION_DEFAULT%/,
              ""
            ).gsub(
              /%MSAD_INJECTION_DEVELOPMENT%/,
              ""
            )
          end

          let(:secrets_yml_modified) do
            default = "    msad:\n"
            default += "      enabled: false\n"
            default += "      metadata_url:\n"
            default += "      icon: account-login\n"
            development = "    msad:\n"
            development += "      enabled: true\n"
            development += "      metadata_url:\n"
            development += "      icon: account-login\n"

            secrets_yml_template.gsub(
              /%MSAD_INJECTION_DEFAULT%/,
              default
            ).gsub(
              /%MSAD_INJECTION_DEVELOPMENT%/,
              development
            )
          end

          it "enables the MSAD authentication by modifying the secrets.yml file" do
            allow(File).to receive(:read).and_return(secrets_yml)
            expect(File).to receive(:read)
            allow(File).to receive(:readlines).and_return(secrets_yml.lines)
            expect(File).to receive(:readlines)
            expect(File).to receive(:open).with(anything, "w") do |&block|
              file = double
              expect(file).to receive(:puts).with(secrets_yml_modified)
              block.call(file)
            end
            expect(subject).to receive(:say_status).with(
              :insert,
              "config/secrets.yml",
              :green
            )

            subject.enable_authentication
          end

          context "with MSAD already enabled" do
            it "reports identical status" do
              allow(YAML).to receive(:safe_load).and_return(
                "default" => { "omniauth" => { "msad" => {} } }
              )
              expect(YAML).to receive(:safe_load)
              expect(subject).to receive(:say_status).with(
                :identical,
                "config/secrets.yml",
                :blue
              )

              subject.enable_authentication
            end
          end
        end
      end
    end
  end
end
