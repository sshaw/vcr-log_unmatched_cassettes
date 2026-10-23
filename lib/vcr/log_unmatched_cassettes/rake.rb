# frozen_string_literal: true

require "rake"
require "csv"
require "fileutils"
require "vcr/log_unmatched_cassettes"

module VCR
  module LogUnmatchedCassettes
    module Rake
      class << self
        # Deletes the files listed in the +cassette+ column of the latest
        # report and returns the paths that were removed.
        def delete_cassettes(report = latest_report_file)
          return [] unless report && File.file?(report)

          report_path = File.expand_path(report)
          deleted     = []

          CSV.foreach(report, headers: true) do |row|
            path = row["cassette"]
            next if path.nil? || path.strip.empty?

            path = File.expand_path(path)
            next if path == report_path || deleted.include?(path) || !File.file?(path)

            FileUtils.rm(path)
            deleted << path
          end

          deleted
        end

        private

        # The most recently written report. Reports from previous runs are
        # ignored, as their cassettes have presumably been dealt with already.
        def latest_report_file
          Dir[File.join(report_dir, "#{REPORT_PREFIX}.*.csv")]
            .select { |path| File.file?(path) }
            .max_by { |path| [File.mtime(path), File.basename(path)] }
        end

        def report_dir
          LogUnmatchedCassettes.output_dir || LogUnmatchedCassettes.default_output_dir
        end
      end
    end
  end
end

namespace :vcr do
  namespace :log_unmatched_cassettes do
    desc "Delete the cassettes listed in the latest vcr-unmatched-cassettes report"
    task :delete_cassettes do
      log   = VCR::LogUnmatchedCassettes
      tasks = VCR::LogUnmatchedCassettes::Rake

      if log.enabled == false
        warn "[VCR::LogUnmatchedCassettes] Disabled, not deleting anything."
        next
      end

      dir     = log.output_dir || log.default_output_dir
      deleted = tasks.delete_cassettes

      if deleted.empty?
        warn "[VCR::LogUnmatchedCassettes] Nothing to delete from the latest report in #{dir}."
        next
      end

      warn "[VCR::LogUnmatchedCassettes] Deleted #{deleted.size} cassette(s) from the latest report in #{dir}:"

      deleted.each { |path| warn "  #{path}" }
    end
  end
end
