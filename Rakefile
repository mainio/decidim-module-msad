# frozen_string_literal: true

require "decidim/dev/common_rake"

desc "Generates a dummy app for testing"
task test_app: "decidim:generate_external_test_app" do
  Dir.chdir("spec/decidim_dummy_app") do
    system("bundle exec rails generate decidim:msad:install --test-initializer true")
  end
end

desc "Generates a development app."
task development_app: "decidim:generate_external_development_app" do
  Dir.chdir("development_app") do
    system("bundle exec rails generate decidim:msad:install")
  end
end
