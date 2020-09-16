# frozen_string_literal: true

require "decidim/dev"

ENV["RAILS_ENV"] ||= "test"

require "simplecov" if ENV["SIMPLECOV"]

require "decidim/core"
require "decidim/core/test"
require "decidim/admin/test"

require "decidim/dev/test/rspec_support/component"
require "decidim/dev/test/rspec_support/authorization"
