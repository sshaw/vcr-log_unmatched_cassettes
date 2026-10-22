# frozen_string_literal: true

require "vcr"
require "fileutils"
require "tmpdir"
require "csv"

module VCR
  module LogUnmatchedCassettes
    module MinitestHook         # :nodoc:
      def after_teardown
        super

        vcr_error = VCR::LogUnmatchedCassettes.find_vcr_error($!)
        return unless vcr_error

        cassette = VCR.current_cassette
        return unless cassette

        location = "#{self.class.name}##{name}"
        path     = cassette.respond_to?(:file) ? cassette.file : cassette.name.to_s

        VCR::LogUnmatchedCassettes.record(location, path)
      end
    end

    class << self
      attr_accessor :enabled, :output_dir

      def install
        self.enabled = true if enabled.nil?
        self.output_dir = defined?(Rails) && Rails.respond_to?(:root) ? Rails.root.join("tmp").to_s : Dir.tmpdir

        @failures = []

        if defined?(::RSpec)
          install_rspec
        elsif defined?(Minitest)
          install_minitest
        else
          raise "VCR::LogUnmatchedCassettes requires RSpec or Minitest. Neither was found."
        end
      end

      def record(location, cassette_path)
        return if !enabled || cassette_path.nil? || cassette_path.empty?

        @failures << [location, cassette_path]
      end

      def write_report
        return if @failures.empty?

        FileUtils.mkdir_p(output_dir)

        timestamp = Time.now.strftime("%Y%m%d%H%M%S")
        filename  = File.join(output_dir, "vcr-unmatched-cassettes.#{timestamp}.csv")

        CSV.open(filename, "w") do |csv|
          csv << %w[test cassette]

          @failures.each do |test, cassette|
            csv << [test, cassette]
          end
        end

        warn "\n[VCR::LogUnmatchedCassettes] Wrote #{@failures.size} failed cassette(s) to: #{filename}"
      end

      # Walks the exception + cause chain looking for UnhandledHTTPRequestError
      def find_vcr_error(exception)
        current = exception

        while current
          return current if current.is_a?(VCR::Errors::UnhandledHTTPRequestError)
          current = current.cause
        end

        nil
      end

      private

      def install_rspec
        ::RSpec.configure do |config|
          config.after(:each) do |example|
            vcr_error = VCR::LogUnmatchedCassettes.find_vcr_error(example.exception)
            next unless vcr_error

            cassette = VCR.current_cassette
            next unless cassette

            # :location is "./spec/foo_spec.rb:42"
            VCR::LogUnmatchedCassettes.record(example.metadata[:location], cassette.file)
          end

          config.after(:suite) do
            VCR::LogUnmatchedCassettes.write_report
          end
        end
      end

      def install_minitest
        Minitest::Test.prepend(MinitestHook)

        Minitest.after_run { VCR::LogUnmatchedCassettes.write_report }
      end
    end
  end
end
