# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "rails/railtie"

require "protobufable"

module Protobufable
  # Installs the renderers and the request body parser on boot.
  class Railtie < ::Rails::Railtie
    initializer "protobufable.install" do
      Protobufable.install!
    end
  end
end
