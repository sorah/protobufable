# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

# The problem gem integration, required on its own because problem is not a dependency of
# protobufable: a host that renders no problem details never loads it.
#
#   require "protobufable/problem"
#
# Brings Protobufable::ProblemTypeOptions with it, the message an application annotates its
# problem type enum with. Requiring it registers that descriptor, so an application must not
# also generate protobufable/problem.proto itself.

require "protobufable/problem_pb"

module Protobufable
  # The problem gem integration: a catalogue backed by a protobuf enum, and protobuf messages in
  # a problem document. Code in here names the problem gem's own constants as `::Problem`.
  module Problem
  end
end

require "protobufable/problem/typeable"
require "protobufable/problem/information"
require "protobufable/problem/retry_info"
