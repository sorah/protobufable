# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

# The problem gem integration, required on its own because problem is not a dependency of
# protobufable: a host that renders no problem details never loads it.
#
#   require "protobufable/problem"

require "protobufable/problem/typeable"
