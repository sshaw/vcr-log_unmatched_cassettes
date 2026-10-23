# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe "VCR::LogUnmatchedCassettes::Railtie" do
  # A minimal stand-in for Rails so the railtie can be loaded without Rails.
  def fixture_source
    <<~RUBY
      module Rails
        class Railtie
          def self.rake_tasks(&block)
            (@rake_tasks ||= []) << block
          end

          def self.rake_task_blocks
            @rake_tasks || []
          end
        end
      end

      require "vcr/log_unmatched_cassettes"

      blocks = VCR::LogUnmatchedCassettes::Railtie.rake_task_blocks

      abort "expected 1 rake task block, got \#{blocks.size}" unless blocks.size == 1

      blocks.each(&:call)

      abort "rake task not defined" unless Rake::Task.task_defined?("vcr:log_unmatched_cassettes:delete_cassettes")

      puts "loaded"
    RUBY
  end

  it "loads the rake task when Rails is present" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "railtie_fixture.rb")
      File.write(path, fixture_source)

      out, err, status = Open3.capture3("bundle", "exec", "ruby", path)

      expect(status).to be_success, "#{out}\n#{err}"
      expect(out).to include("loaded")
    end
  end
end
