# VCR::LogUnmatchedCassettes

Make finding and re-recording unmatched [VCR cassettes](https://github.com/vcr/vcr) (test that fail due to `VCR::Errors::UnhandledHTTPRequestError`)
easier by logging the test and unmatched cassette paths to a CSV.

[![Ruby](https://github.com/sshaw/vcr-log_unmatched_cassettes/actions/workflows/main.yml/badge.svg?branch=master)](https://github.com/sshaw/vcr-log_unmatched_cassettes/actions/workflows/main.yml)

## Usage

In your `Gemfile`

```rb
# development for Rake task access
gem "vcr-log_unmatched_cassettes", :group => %w[test development]
```

In your spec configuration, after loading VCR, call:
```rb
VCR::LogUnmatchedCassettes.install
```

Now tests that fail due to VCR being able to unmatch the request (`VCR::Errors::UnhandledHTTPRequestError`) will be output to the system's temp directory in a CSV.
If you're using Rails it will be output to `./tmp`.

## Deleting Cassettes

Load the Rake task to delete cassettes listed in the `cassette` column of the latest report:

```rb
# Rakefile
require "vcr/log_unmatched_cassettes/rake"
```

Then run:

```
rake vcr:log_unmatched_cassettes:delete_cassettes
```

Under Rails it is loaded automatically via a Railtie.

## Why?

When tests fail due to unmatched HTTP requests the path is output within a large blob of text. This may be fine for a couple of tests but
with large amounts of tests the path can be a pain track down. This becomes worse when one needs the paths for multiple tests.

Often one needs the path solely to delete the cassette and re-record it. This is often preferred to using VCR's `record: :all` globally as `:all` is a bit heavy-handed.

`record: :all` can be applied per test, but this requires modifying the test so that it can be scoped to `:all`.

Removing all cassettes is an option but this can clutter your git history with needless and _very_ bloated diffs.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Author

Skye Shaw [sshaw AT gmail.com]
