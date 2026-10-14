# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "rails/railtie"
require "action_dispatch/railtie"

require "protobufable"

module Protobufable
  # Installs the renderers and the request body parser on boot, classifies a broken
  # `buf.validate` rule as a 400, and registers the Alba `:timestamp` type when Alba is loaded.
  class Railtie < ::Rails::Railtie
    # A string, so protovalidate stays unloaded for an application that does not use it.
    # `config.action_dispatch` is answered by method_missing, which RBS cannot describe.
    # steep:ignore:start
    config.action_dispatch.rescue_responses["Protobufable::RequestValidatable::InvalidMessage"] = :bad_request
    # steep:ignore:end

    initializer "protobufable.install" do
      Protobufable.install!
    end

    # Leaves a `:timestamp` type the application registered itself in place.
    initializer "protobufable.alba" do
      next unless defined?(::Alba)

      ::Alba.find_type(:timestamp)
    rescue ::Alba::UnsupportedType
      require "protobufable/alba_binding"
      Protobufable::AlbaBinding.register_timestamp_type!
    end
  end
end
