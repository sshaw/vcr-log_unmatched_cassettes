# frozen_string_literal: true

module VCR
  module LogUnmatchedCassettes
    class Railtie < ::Rails::Railtie
      rake_tasks do
        load File.expand_path("rake.rb", __dir__)
      end
    end
  end
end
