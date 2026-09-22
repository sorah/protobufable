# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "google/protobuf"
require "google/protobuf/well_known_types"

require "protobufable/version"
require "protobufable/json_type"
require "protobufable/request_parseable"
require "protobufable/renderers"

# Protocol Buffers as the schema of record for a Rails API: request bodies, stored columns,
# error catalogues and responses all described by generated message classes.
#
# Each integration is required on its own, so a host pays only for what it uses:
#
#   require "protobufable/problem"        # needs the problem gem
#   require "protobufable/protovalidate"  # needs the protovalidate gem
#   require "protobufable/alba_binding"   # needs the alba gem
module Protobufable
  # Raised when a declaration cannot be honoured, such as an enum value the catalogue does not
  # define or a serializer that has drifted from its message.
  class Error < StandardError; end

  # Registers the renderers and installs the request body parser. Called by the railtie on
  # boot; a Rack host, or a spec that never boots Rails, calls it itself. Installing twice is
  # harmless.
  #
  # @return [void]
  #: () -> void
  def self.install!
    Renderers.install!
    ActionDispatch::Request.prepend(RequestParseable::RequestPatch)
  end
end

require "protobufable/railtie" if defined?(Rails::Railtie)
