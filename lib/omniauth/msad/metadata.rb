# frozen_string_literal: true

module OmniAuth
  module MSAD
    class Metadata < OneLogin::RubySaml::Metadata
      def generate(settings, pretty_print = false)
        metadata_signed = settings.security.delete(:metadata_signed)
        settings.security[:metadata_signed] = false

        meta_xml = super(settings)
        meta_doc = XMLSecurity::Document.new(meta_xml)
        add_tags_to(meta_doc.root, settings.sp_metadata) if settings.sp_metadata

        sign_document!(meta_doc, settings) if metadata_signed
        return meta_doc.write("", 1) if pretty_print

        meta_doc.to_s
      end

      private

      def add_tags_to(parent, tags)
        tags.each do |tag|
          element = parent.add_element "md:#{tag[:name]}", tag[:attributes]
          element.text = tag[:content] if tag[:content]
          add_tags_to(element, tag[:children]) if tag[:children].is_a?(Array)
        end
      end

      def sign_document!(document, settings)
        return unless settings.security[:metadata_signed]
        return unless settings.private_key
        return unless settings.certificate

        # embed signature
        private_key = settings.get_sp_key
        document.sign_document(
          private_key,
          cert,
          settings.security[:signature_method],
          settings.security[:digest_method]
        )
      end
    end
  end
end
