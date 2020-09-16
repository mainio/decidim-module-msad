# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Msad
    module MailInterceptors
      describe GeneratedRecipientsInterceptor do
        let(:mailer_defaults) { { template_path: "custom", template_name: "mail" } }

        context "when the auto-generated email domain is not defined" do
          let(:message) { double }

          before do
            allow(Decidim::Msad).to receive(:auto_email_domain).and_return(nil)
          end

          it "does nothing" do
            expect(message).not_to receive(:to)
            expect(message).not_to receive(:cc)
            expect(message).not_to receive(:bcc)
            expect(message).not_to receive(:perform_deliveries)

            described_class.delivering_email(message)
          end
        end

        context "when the auto-generated email domain is defined" do
          let(:domain) { Decidim::Msad.auto_email_domain }
          let(:from_email) { "test@#{domain}" }
          let(:generated_email) do
            digest = Digest::MD5.hexdigest("test")
            "msad-#{digest}@#{domain}"
          end

          context "with an auto-generated email in the 'to' header" do
            it "does not deliver the email" do
              expect do
                ActionMailer::Base.mail(
                  mailer_defaults.merge(
                    to: generated_email,
                    from: from_email
                  )
                ).deliver
              end.not_to change(ActionMailer::Base.deliveries, :count)
            end

            context "with other recipients" do
              it "delivers the email only to the other recipients" do
                expect do
                  ActionMailer::Base.mail(
                    mailer_defaults.merge(
                      to: [generated_email, "other@recipient.com"],
                      from: from_email
                    )
                  ).deliver
                end.to change(ActionMailer::Base.deliveries, :count).by(1)

                mail = ActionMailer::Base.deliveries.last
                expect(mail.to).to eq(["other@recipient.com"])
              end
            end
          end

          context "with an auto-generated email in the 'cc' header" do
            it "does not deliver the email" do
              expect do
                ActionMailer::Base.mail(
                  mailer_defaults.merge(
                    to: "jdoe@foo.bar",
                    cc: generated_email,
                    from: from_email
                  )
                ).deliver
              end.to change(ActionMailer::Base.deliveries, :count).by(1)

              mail = ActionMailer::Base.deliveries.last
              expect(mail.to).to eq(["jdoe@foo.bar"])
              expect(mail.cc).to be_empty
            end

            context "with other recipients" do
              it "delivers the email only to the other recipients" do
                expect do
                  ActionMailer::Base.mail(
                    mailer_defaults.merge(
                      to: "jdoe@foo.bar",
                      cc: [generated_email, "other@recipient.com"],
                      from: from_email
                    )
                  ).deliver
                end.to change(ActionMailer::Base.deliveries, :count).by(1)

                mail = ActionMailer::Base.deliveries.last
                expect(mail.to).to eq(["jdoe@foo.bar"])
                expect(mail.cc).to eq(["other@recipient.com"])
              end
            end
          end

          context "with an auto-generated email in the 'bcc' header" do
            it "does not deliver the email" do
              expect do
                ActionMailer::Base.mail(
                  mailer_defaults.merge(
                    to: "jdoe@foo.bar",
                    cc: "cc@foo.bar",
                    bcc: generated_email,
                    from: from_email
                  )
                ).deliver
              end.to change(ActionMailer::Base.deliveries, :count).by(1)

              mail = ActionMailer::Base.deliveries.last
              expect(mail.to).to eq(["jdoe@foo.bar"])
              expect(mail.cc).to eq(["cc@foo.bar"])
              expect(mail.bcc).to be_empty
            end

            context "with other recipients" do
              it "delivers the email only to the other recipients" do
                expect do
                  ActionMailer::Base.mail(
                    mailer_defaults.merge(
                      to: "jdoe@foo.bar",
                      cc: "cc@foo.bar",
                      bcc: [generated_email, "other@recipient.com"],
                      from: from_email
                    )
                  ).deliver
                end.to change(ActionMailer::Base.deliveries, :count).by(1)

                mail = ActionMailer::Base.deliveries.last
                expect(mail.to).to eq(["jdoe@foo.bar"])
                expect(mail.cc).to eq(["cc@foo.bar"])
                expect(mail.bcc).to eq(["other@recipient.com"])
              end
            end
          end
        end
      end
    end
  end
end
