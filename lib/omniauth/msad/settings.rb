# frozen_string_literal: true

module OmniAuth
  module MSAD
    class Settings < OneLogin::RubySaml::Settings
      attr_accessor :sp_metadata
    end
  end
end
