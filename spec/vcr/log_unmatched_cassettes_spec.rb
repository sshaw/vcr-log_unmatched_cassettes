# frozen_string_literal: true

require "open3"
require "tmpdir"
require "fileutils"
require "csv"

RSpec.describe VCR::LogUnmatchedCassettes do
  def unmatched_error
    request = Struct.new(:method, :uri, :headers, :body).new("get", "http://example.com/", {}, "")
    VCR::Errors::UnhandledHTTPRequestError.new(request)
  end

  def wrap_with_cause(error)
    begin
      raise error
    rescue
      raise "something wrapped the VCR error"
    end
  rescue StandardError => wrapper
    wrapper
  end

  def report_files
    Dir[File.join(@dir, "*.csv")]
  end

  def rspec_fixture_source(install = true)
    install_line = install ? "VCR::LogUnmatchedCassettes.install" : ""

    <<~RUBY
      require "vcr"
      require "vcr/log_unmatched_cassettes"

      dir = __dir__

      VCR.configure do |config|
        config.cassette_library_dir = File.join(dir, "cassettes")
      end

      #{install_line}
      VCR::LogUnmatchedCassettes.output_dir = File.join(dir, "output")

      def unmatched_error
        request = Struct.new(:method, :uri, :headers, :body).new("get", "http://example.com/", {}, "")
        VCR::Errors::UnhandledHTTPRequestError.new(request)
      end

      RSpec.describe "unmatched cassettes" do
        around(:each) do |example|
          cassette = example.metadata[:cassette]

          if cassette
            VCR.use_cassette(cassette) { example.run }
          else
            example.run
          end
        end

        it "logs a direct UnhandledHTTPRequestError", cassette: "direct" do
          raise unmatched_error
        end

        it "logs a nested UnhandledHTTPRequestError", cassette: "nested" do
          begin
            raise unmatched_error
          rescue
            raise "wrapped"
          end
        end

        it "does not log a spec that is not using VCR" do
          raise "boom"
        end

        it "does not log a VCR spec that failed for another reason", cassette: "other" do
          raise "some other error"
        end
      end
    RUBY
  end

  def run_fixture(dir, source, filename)
    File.write(File.join(dir, filename), source)

    out, err, _status = Open3.capture3("bundle", "exec", "rspec", File.join(dir, filename), "--format", "progress")
    "#{out}\n#{err}"
  end

  def read_report(dir)
    files = Dir[File.join(dir, "output", "*.csv")]

    return [] if files.empty?

    CSV.read(files.first)
  end

  def minitest_fixture_source(install = true)
    install_line = install ? "VCR::LogUnmatchedCassettes.install" : ""

    <<~RUBY
      require "minitest/autorun"
      require "vcr"
      require "vcr/log_unmatched_cassettes"

      dir = __dir__

      VCR.configure do |config|
        config.cassette_library_dir = File.join(dir, "cassettes")
      end

      #{install_line}
      VCR::LogUnmatchedCassettes.output_dir = File.join(dir, "output")

      def unmatched_error
        request = Struct.new(:method, :uri, :headers, :body).new("get", "http://example.com/", {}, "")
        VCR::Errors::UnhandledHTTPRequestError.new(request)
      end

      class UnmatchedCassettesTest < Minitest::Test
        def after_teardown
          super
          VCR.eject_cassette
        end

        def test_direct
          VCR.insert_cassette("direct")
          raise unmatched_error
        end

        def test_nested
          VCR.insert_cassette("nested")
          begin
            raise unmatched_error
          rescue
            raise "wrapped"
          end
        end

        def test_other
          VCR.insert_cassette("other")
          raise "boom"
        end

        def test_no_vcr
          raise "boom"
        end
      end
    RUBY
  end

  def run_minitest_fixture(dir, source, filename)
    File.write(File.join(dir, filename), source)

    out, err, _status = Open3.capture3("bundle", "exec", "ruby", File.join(dir, filename))
    "#{out}\n#{err}"
  end

  def fixture_dir(name)
    dir = File.join(@tmpdir, name)
    FileUtils.mkdir_p(dir)
    dir
  end

  before(:all) do
    @tmpdir = Dir.mktmpdir

    @install_dir = fixture_dir("rspec_with_install")
    @install_output = run_fixture(@install_dir, rspec_fixture_source, "with_install_spec.rb")
    @rows = read_report(@install_dir)

    @no_install_dir = fixture_dir("rspec_without_install")
    @no_install_output = run_fixture(@no_install_dir, rspec_fixture_source(false), "without_install_spec.rb")

    @mt_install_dir = fixture_dir("minitest_with_install")
    @mt_install_output = run_minitest_fixture(@mt_install_dir, minitest_fixture_source, "with_install_test.rb")
    @mt_rows = read_report(@mt_install_dir)

    @mt_no_install_dir = fixture_dir("minitest_without_install")
    @mt_no_install_output = run_minitest_fixture(@mt_no_install_dir, minitest_fixture_source(false), "without_install_test.rb")
  end

  after(:all) do
    FileUtils.remove_entry(@tmpdir)
  end

  describe ".find_vcr_error" do
    it "returns the UnhandledHTTPRequestError itself" do
      error = unmatched_error

      expect(described_class.find_vcr_error(error)).to be(error)
    end

    it "finds an UnhandledHTTPRequestError nested in the cause chain" do
      wrapped = wrap_with_cause(unmatched_error)

      expect(described_class.find_vcr_error(wrapped)).to be_a(VCR::Errors::UnhandledHTTPRequestError)
    end

    it "returns nil for an error that is not VCR related" do
      expect(described_class.find_vcr_error(StandardError.new("boom"))).to be_nil
    end

    it "returns nil when there is no error" do
      expect(described_class.find_vcr_error(nil)).to be_nil
    end
  end

  describe ".record" do
    before do
      @dir = Dir.mktmpdir
      described_class.install
      described_class.enabled = true
      described_class.output_dir = @dir
    end

    after do
      FileUtils.remove_entry(@dir)
    end

    it "writes the spec location and cassette path to the report" do
      described_class.record("spec/foo_spec.rb:42", "cassettes/foo.yml")
      described_class.write_report

      expect(report_files.size).to eq(1)
      expect(CSV.read(report_files.first)).to eq([["test", "cassette"], ["spec/foo_spec.rb:42", "cassettes/foo.yml"]])
    end

    it "does not write a report when disabled" do
      described_class.enabled = false

      described_class.record("spec/foo_spec.rb:42", "cassettes/foo.yml")
      described_class.write_report

      expect(report_files).to be_empty
    end

    it "does not write a report when the cassette path is empty" do
      described_class.record("spec/foo_spec.rb:42", "")
      described_class.write_report

      expect(report_files).to be_empty
    end
  end

  describe "RSpec hook integration" do
    it "ran all four failing examples" do
      expect(@install_output).to include("4 examples, 4 failures")
    end

    it "logs the spec location and cassette path for a direct UnhandledHTTPRequestError" do
      expect(@rows.map { |row| row[1] }).to include(a_string_matching(%r{cassettes/direct\.yml$}))
      expect(@rows.map { |row| row[0] }).to include(a_string_matching(%r{with_install_spec\.rb:\d+$}))
    end

    it "logs the spec location and cassette path for a nested UnhandledHTTPRequestError" do
      expect(@rows.map { |row| row[1] }).to include(a_string_matching(%r{cassettes/nested\.yml$}))
      expect(@rows.map { |row| row[0] }).to include(a_string_matching(%r{with_install_spec\.rb:\d+$}))
    end

    it "does not log specs that fail without using VCR or for another reason" do
      data = @rows.drop(1)

      expect(data.size).to eq(2)
      expect(@rows.map { |row| row[1] }).not_to include(a_string_matching(%r{cassettes/other\.yml$}))
    end

    it "does not log a VCR error when install was not called" do
      expect(@no_install_output).to include("4 examples, 4 failures")
      expect(read_report(@no_install_dir)).to be_empty
    end
  end

  describe "Minitest hook integration" do
    it "ran all four failing tests" do
      expect(@mt_install_output).to include("4 runs")
    end

    it "logs the test and cassette for a direct UnhandledHTTPRequestError" do
      expect(@mt_rows.map { |row| row[0] }).to include("UnmatchedCassettesTest#test_direct")
      expect(@mt_rows.map { |row| row[1] }).to include(a_string_matching(%r{cassettes/direct\.yml$}))
    end

    it "logs the test and cassette for a nested UnhandledHTTPRequestError" do
      expect(@mt_rows.map { |row| row[0] }).to include("UnmatchedCassettesTest#test_nested")
      expect(@mt_rows.map { |row| row[1] }).to include(a_string_matching(%r{cassettes/nested\.yml$}))
    end

    it "does not log tests that fail without using VCR or for another reason" do
      data = @mt_rows.drop(1)

      expect(data.size).to eq(2)
      expect(@mt_rows.map { |row| row[1] }).not_to include(a_string_matching(%r{cassettes/other\.yml$}))
    end

    it "does not log a VCR error when install was not called" do
      expect(@mt_no_install_output).to include("4 runs")
      expect(read_report(@mt_no_install_dir)).to be_empty
    end
  end
end
