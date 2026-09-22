# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
# The generated message classes the suite exercises. Not shipped with the gem: they exist to
# give the specs real descriptors to work against.
$LOAD_PATH.unshift(File.expand_path("fixtures", __dir__))

require "json"
require "rack/mock"
require "protobufable"

require "protobufable/problem_pb"
require "protobufable/testing/v1/fixtures_pb"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
