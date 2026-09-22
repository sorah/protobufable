# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

# The protovalidate integration, required on its own because protovalidate is not a dependency
# of protobufable: a host that declares no buf.validate rules never loads it.
#
#   require "protobufable/protovalidate"

require "protobufable/bad_request"
require "protobufable/column_validatable"
require "protobufable/field_path"
require "protobufable/request_validatable"
