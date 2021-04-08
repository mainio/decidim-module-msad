# frozen_string_literal: true

module Decidim
  module Msad
    module MailInterceptors
      # Prevents sending emails to the auto-generated email addresses.
      class GeneratedRecipientsInterceptor
        class << self
          def delivering_email(message)
            # Remove the auto-generated email from the message recipients
            message.to = message.to.reject { |email| matches_auto_email?(email) } if message.to
            message.cc = message.cc.reject { |email| matches_auto_email?(email) } if message.cc
            message.bcc = message.bcc.reject { |email| matches_auto_email?(email) } if message.bcc

            # Prevent delivery in case there are no recipients on the email
            message.perform_deliveries = false if message.to.empty?
          end

          private

          def matches_auto_email?(email)
            Decidim::Msad.tenants.each do |tenant|
              return true if tenant.auto_email_matches?(email)
            end

            false
          end
        end
      end
    end
  end
end
