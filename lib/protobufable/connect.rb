# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

# The connect_rpc_rails integration, required on its own because neither connect_rpc_rails nor
# problem is a dependency of protobufable: a host that serves no Connect RPC never loads it.
#
#   require "protobufable/connect"

require "protobufable/problem"

module Protobufable
  # The connect_rpc_rails integration: problems answered as Connect errors.
  module Connect
  end
end

require "protobufable/connect/problem_rescuable"
