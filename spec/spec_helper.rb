# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "rack/mock"
require "protobufable"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
