# frozen_string_literal: true

require "tmpdir"
require "csv"
require "fileutils"
require "rake"
require "vcr/log_unmatched_cassettes/rake"

RSpec.describe "vcr:log_unmatched_cassettes:delete_cassettes" do
  def log
    VCR::LogUnmatchedCassettes
  end

  def rake_methods
    VCR::LogUnmatchedCassettes::Rake
  end

  def rake_task
    Rake::Task["vcr:log_unmatched_cassettes:delete_cassettes"]
  end

  def write_report(name, cassettes, time = Time.now)
    path = File.join(@dir, name)

    CSV.open(path, "w") do |csv|
      csv << %w[test cassette]
      cassettes.each { |cassette| csv << ["spec/foo_spec.rb:1", cassette] }
    end

    File.utime(time, time, path)
    path
  end

  def cassette(name)
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\n")
    path
  end

  before do
    @dir = Dir.mktmpdir
    log.output_dir = @dir
    log.enabled = nil
    rake_task.reenable
  end

  after do
    FileUtils.remove_entry(@dir)
    log.output_dir = nil
    log.enabled = nil
  end

  describe "VCR::LogUnmatchedCassettes::Rake.delete_cassettes" do
    it "deletes the cassettes listed in the latest report only" do
      stale = cassette("cassettes/stale.yml")
      current = cassette("cassettes/current.yml")

      write_report("vcr-unmatched-cassettes.20240101000000.csv", [stale], Time.now - 60)
      write_report("vcr-unmatched-cassettes.20240202000000.csv", [current])

      expect(rake_methods.delete_cassettes).to eq([current])
      expect(File).not_to exist(current)
      expect(File).to exist(stale)
    end

    it "ignores duplicate and missing cassette paths" do
      current = cassette("cassettes/current.yml")
      missing = File.join(@dir, "cassettes", "missing.yml")

      write_report("vcr-unmatched-cassettes.20240202000000.csv", [current, current, missing])

      expect(rake_methods.delete_cassettes).to eq([current])
    end

    it "returns an empty list when there is no report" do
      expect(rake_methods.delete_cassettes).to eq([])
    end
  end

  describe "the rake task" do
    it "deletes the cassettes listed in the latest report" do
      stale = cassette("cassettes/stale.yml")
      current = cassette("cassettes/current.yml")

      write_report("vcr-unmatched-cassettes.20240101000000.csv", [stale], Time.now - 60)
      write_report("vcr-unmatched-cassettes.20240202000000.csv", [current])

      rake_task.invoke

      expect(File).not_to exist(current)
      expect(File).to exist(stale)
    end

    it "does not delete anything when disabled" do
      current = cassette("cassettes/current.yml")

      write_report("vcr-unmatched-cassettes.20240202000000.csv", [current])
      log.enabled = false

      rake_task.invoke

      expect(File).to exist(current)
    end

    it "does not delete anything when there is no report" do
      rake_task.invoke

      expect(Dir[File.join(@dir, "*.csv")]).to be_empty
    end

    it "falls back to the default output directory when none is set" do
      current = cassette("cassettes/current.yml")

      write_report("vcr-unmatched-cassettes.20240202000000.csv", [current])
      log.output_dir = nil
      allow(log).to receive(:default_output_dir).and_return(@dir)

      rake_task.invoke

      expect(File).not_to exist(current)
    end
  end
end
