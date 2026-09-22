# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "active_model"
require "active_support/json"

require "protobufable"

module Protobufable
  # An ActiveModel type storing a protobuf message in a native `json` or `jsonb` column.
  #
  # Encoding goes through the message's own `encode_json` and `decode_json`, so the stored
  # document is constrained to the protobuf schema rather than to whatever a Hash happened to
  # hold. Being a type rather than a `serialize` coder is what buys dirty tracking, casting
  # from a Hash, and a column the adapter knows is JSON.
  #
  # @example A column that is never null in Ruby
  #   class Widget < ApplicationRecord
  #     attribute :settings, Protobufable::JsonType.new(Internal::WidgetSettings),
  #       default: -> { Internal::WidgetSettings.new }
  #   end
  class JsonType < ActiveModel::Type::Value
    # @return [Class] the generated message class this column holds
    attr_reader :message_class #: Google::Protobuf::_MessageClass

    # @param message_class [Class] the generated message class this column holds
    # @param nil_as_default [Boolean] whether a null column reads back as an empty message,
    #   for a nullable column whose Ruby value is semantically non-null
    # @return [void]
    #: (Google::Protobuf::_MessageClass message_class, ?nil_as_default: bool) -> void
    def initialize(message_class, nil_as_default: false)
      super()
      @message_class = message_class
      @nil_as_default = nil_as_default
    end

    # @return [Symbol] always `:json`, so Rails and the adapter treat the column as JSON
    #: () -> Symbol
    def type = :json

    # Decodes a stored document into a message.
    #
    # Unknown fields are tolerated: during a rolling deploy a row written by a newer schema has
    # to stay readable on a node that has not picked it up yet.
    #
    # @param value [String, nil] the document as the adapter hands it back
    # @return [Object, nil] the decoded message, or nil for a null column
    #: (String? value) -> untyped
    def deserialize(value)
      return @message_class.new if value.nil? && @nil_as_default
      return if value.nil?

      @message_class.decode_json(value, ignore_unknown_fields: true)
    end

    # Encodes a message for storage.
    #
    # Defaults are emitted so the stored shape does not depend on which fields happened to be
    # set, which is what makes {#changed_in_place?} meaningful and spares anything reading the
    # column in SQL from telling absent from default.
    #
    # @param value [Object, nil] the message to store
    # @return [String, nil] the document to write, or nil
    #: (untyped value) -> String?
    def serialize(value)
      return if value.nil?

      @message_class.encode_json(value, emit_defaults: true)
    end

    # Coerces an assigned value into a message, accepting what a form, a fixture or a seed
    # would supply as well as a message itself.
    #
    # @param value [Object, String, Hash, nil]
    # @return [Object, nil] the message, or the value unchanged when it is none of those
    #: (untyped value) -> untyped
    def cast(value)
      return deserialize(nil) if value.nil?

      case value
      when @message_class
        value
      when ::String
        deserialize(value)
      when ::Hash
        deserialize(::ActiveSupport::JSON.encode(value))
      else
        value
      end
    end

    # Compares decoded messages rather than encoded text: a jsonb column hands back a
    # canonicalized document whose key order and spacing need not match what `encode_json`
    # produced, which would otherwise read as a change on every load.
    #
    # @param raw_old_value [String, nil] the document as it was loaded
    # @param new_value [Object, nil] the message currently held
    # @return [Boolean]
    #: (String? raw_old_value, untyped new_value) -> bool
    def changed_in_place?(raw_old_value, new_value)
      deserialize(raw_old_value) != new_value
    end
  end
end
