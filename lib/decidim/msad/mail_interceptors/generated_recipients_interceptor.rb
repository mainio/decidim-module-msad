# frozen_string_literal: true

module Decidim
  module Msad
    module MailInterceptors
      # Prevents sending emails to the auto-generated email addresses.
      class GeneratedRecipientsInterceptor
        def self.delivering_email(message)
          return unless Decidim::Msad.auto_email_domain

          # Regexp to match the auto-generated emails
          regexp = /^msad-[a-z0-9]{32}@#{Decidim::Msad.auto_email_domain}$/

          # Remove the auto-generated email from the message recipients
          message.to = message.to.reject { |email| email =~ regexp } if message.to
          message.cc = message.cc.reject { |email| email =~ regexp } if message.cc
          message.bcc = message.bcc.reject { |email| email =~ regexp } if message.bcc

          # Prevent delivery in case there are no recipients on the email
          message.perform_deliveries = false if message.to.empty?
        end
      end
    end
  end
end
