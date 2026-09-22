# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "active_support/concern"
require "protovalidate"

require "protobufable"
require "protobufable/field_path"
require "protobufable/json_type"

module Protobufable
  # Runs the `buf.validate` rules of every {JsonType} column before the record is saved, so a
  # column holding a message enforces what its .proto declares wherever the record is written:
  # application code, a seed, the console.
  #
  # @example
  #   class ApplicationRecord < ActiveRecord::Base
  #     include Protobufable::ColumnValidatable
  #   end
  #
  # @rbs module-self _ColumnValidatableSelf
  module ColumnValidatable
    extend ActiveSupport::Concern

    # `self` inside an ActiveSupport::Concern block is the including class, which RBS has no
    # way to name.
    # steep:ignore:start
    included do
      validate(:validate_protobuf_message_columns)
    end
    # steep:ignore:end

    # Adds one error per violation, under the attribute that holds the message.
    #
    # @return [void]
    #: () -> void
    private def validate_protobuf_message_columns
      self.class.attribute_types.each do |name, type|
        next unless type.is_a?(JsonType)

        # read_attribute rather than the reader, which a model may have overridden to wrap the
        # message in something of its own.
        message = self[name]
        next if message.nil?

        Protovalidate.collect_violations(message).each do |violation|
          path = FieldPath.render(violation.field, type.message_class)
          errors.add(name, path.empty? ? violation.message : "#{path}: #{violation.message}")
        end
      end
    end
  end
end
