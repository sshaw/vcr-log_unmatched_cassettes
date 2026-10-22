# frozen_string_literal: true

require_relative "lib/vcr/log_unmatched_cassettes/version"

Gem::Specification.new do |spec|
  spec.name = "vcr-log_unmatched_cassettes"
  spec.version = VCR::LogUnmatchedCassettes::VERSION
  spec.authors = ["Skye Shaw"]
  spec.email = ["skye.shaw@gmail.com"]

  spec.summary = "Make finding and re-recording unmatched VCR cassettes easier by logging the test and unmatched cassette paths to a CSV"
  spec.homepage = "https://github.com/sshaw/vcr-log_unmatched_cassettes"
  spec.license = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/sshaw/vcr-log_unmatched_cassettes"

  spec.required_ruby_version = ">= 2.7"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "vcr"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "bundler"
end
