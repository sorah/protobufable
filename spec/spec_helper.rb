# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
# The generated message classes the suite exercises. Not shipped with the gem: they exist to
# give the specs real descriptors to work against.
$LOAD_PATH.unshift(File.expand_path("fixtures", __dir__))

require "active_record"
require "json"
require "rack/mock"
require "protobufable"

require "google/rpc/error_details_pb"
require "protobufable/testing/v1/fixtures_pb"

# One in-memory database for the whole suite. Each :memory: connection is its own empty
# database, so a second establish_connection would drop the tables an earlier spec file
# defined; spec files add their tables to this one.
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
