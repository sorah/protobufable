# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "protobufable"

module Protobufable
  # A `serialize` coder storing a protobuf message as ProtoJSON in a `text` column.
  #
  # It cannot serve a `json` or `jsonb` column. `serialize` layers the coder over the column's
  # own type, which encodes the String {#dump} returns a second time, storing a JSON string
  # literal, and parses a stored object into a Hash before {#load} sees it. Use {JsonType}.
  #
  # @example
  #   class Widget < ApplicationRecord
  #     serialize :settings, coder: Protobufable::JsonCoder.new(Internal::WidgetSettings)
  #   end
  class JsonCoder
    # @return [Class] the generated message class this column holds
    attr_reader :message_class #: Google::Protobuf::_MessageClass

    # @param message_class [Class] the generated message class this column holds
    # @param preserve_proto_fieldnames [Boolean] whether documents are written with the
    #   `.proto` field names (`snake_case`) rather than their lowerCamelCase JSON names
    # @return [void]
    #: (Google::Protobuf::_MessageClass message_class, ?preserve_proto_fieldnames: bool) -> void
    def initialize(message_class, preserve_proto_fieldnames: false)
      @message_class = message_class
      @preserve_proto_fieldnames = preserve_proto_fieldnames
    end

    # Decodes a stored document, tolerating unknown fields as {JsonType#deserialize} does.
    #
    # @param json [String, nil] the stored document
    # @return [Object, nil] the decoded message, or nil for a null column
    # @raise [Error] when handed an already parsed document, as a json column does
    #: (untyped json) -> untyped
    def load(json)
      return if json.nil?

      unless json.is_a?(::String)
        raise Error,
          "#{self.class} received a #{json.class} rather than a String; " \
            "a json or jsonb column needs Protobufable::JsonType instead"
      end

      @message_class.decode_json(json, ignore_unknown_fields: true)
    end

    # Encodes a message, emitting defaults as {JsonType#serialize} does.
    #
    # @param message [Object, nil] the message to store
    # @return [String, nil] the document to write, or nil
    #: (untyped message) -> String?
    def dump(message)
      return if message.nil?

      @message_class.encode_json(
        message,
        emit_defaults: true,
        preserve_proto_fieldnames: @preserve_proto_fieldnames,
      )
    end
  end
end
