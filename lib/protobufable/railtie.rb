# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "rails/railtie"
require "action_dispatch/railtie"

require "protobufable"

module Protobufable
  # Installs the renderers and the request body parser on boot, and classifies a broken
  # `buf.validate` rule as a 400.
  class Railtie < ::Rails::Railtie
    # A string, so protovalidate stays unloaded for an application that does not use it.
    # `config.action_dispatch` is answered by method_missing, which RBS cannot describe.
    # steep:ignore:start
    config.action_dispatch.rescue_responses["Protobufable::RequestValidatable::InvalidMessage"] = :bad_request
    # steep:ignore:end

    initializer "protobufable.install" do
      Protobufable.install!
    end
  end
end
