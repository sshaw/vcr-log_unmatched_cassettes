# frozen_string_literal: true

require "vcr"
require "fileutils"
require "tmpdir"
require "csv"

module VCR
  module LogUnmatchedCassettes
    REPORT_PREFIX = "vcr-unmatched-cassettes"

    # Sentinels from VCR's UnhandledHTTPRequestError message. Used as a fallback
    # when the exception class itself can no longer be reached (see
    # `find_vcr_error`).
    UNHANDLED_REQUEST_MESSAGE = "An HTTP request has been made that VCR does not know how to handle"

    module MinitestHook         # :nodoc:
      # Minitest stores the test's exception by running it through
      # `sanitize_exception` in `capture_exceptions`. A marshable exception is
      # kept as-is, but VCR::Errors::UnhandledHTTPRequestError is not marshable
      # (it memoizes the active cassette), so Minitest "neuters" it into a
      # generic RuntimeError, losing the class and any `cause` chain. Capture
      # the original exception here so it can still be identified in
      # `after_teardown` (where `$!` is nil).
      def sanitize_exception(error)
        @vcr_unmatched_error = error
        super
      end

      def after_teardown
        super

        vcr_error = VCR::LogUnmatchedCassettes.find_vcr_error(@vcr_unmatched_error)
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
        self.output_dir = default_output_dir

        @failures = []

        if defined?(::RSpec)
          install_rspec
        elsif defined?(Minitest)
          install_minitest
        else
          raise "VCR::LogUnmatchedCassettes requires RSpec or Minitest. Neither was found."
        end
      end

      def default_output_dir
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root.join("tmp").to_s
        else
          Dir.tmpdir
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
        filename  = File.join(output_dir, "#{REPORT_PREFIX}.#{timestamp}.csv")

        CSV.open(filename, "w") do |csv|
          csv << %w[test cassette]

          @failures.each do |test, cassette|
            csv << [test, cassette]
          end
        end

        warn "\n[VCR::LogUnmatchedCassettes] Wrote #{@failures.size} failed cassette(s) to: #{filename}"
      end

      # Walks the exception + cause chain looking for UnhandledHTTPRequestError.
      #
      # Some frameworks re-raise VCR's error as a different class after it has
      # crossed a thread boundary (e.g. Capybara's app server). Re-raising a
      # fresh exception object replaces the cause chain, so the VCR error is no
      # longer reachable via `cause`. In that case the only thing left is its
      # message, which VCR's wrapper embeds into its own message. Match on the
      # message as a fallback.
      def find_vcr_error(exception)
        current = exception

        while current
          return current if current.is_a?(VCR::Errors::UnhandledHTTPRequestError)
          return current if current.message.to_s.include?(UNHANDLED_REQUEST_MESSAGE)
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

require "vcr/log_unmatched_cassettes/railtie" if defined?(::Rails::Railtie)
