# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "protobufable"

module Protobufable
  # Renders a `buf.validate.FieldPath` in the spelling the caller sent.
  #
  # A field path is only useful if the client can find the field it names, and a protobuf field
  # has two published names: `preferred_language` in the binary encoding and in ProtoJSON with
  # `preserve_proto_fieldnames`, `preferredLanguage` in ProtoJSON without it. Which one to use
  # is a property of the encoding in play, so each segment is resolved against the descriptor
  # rather than interpolated from the name the violation happened to carry.
  #
  # @example
  #   Protobufable::FieldPath.render(violation.field, CreateWidgetRequest, json_names: true)
  #   #=> "widget.tags[0]"
  module FieldPath
    # Renders a path against the message it was produced from.
    #
    # @param path [Object, nil] a `buf.validate.FieldPath`
    # @param message_class [Class] the message the path is rooted in
    # @param json_names [Boolean] whether to publish `json_name` rather than the proto name
    # @return [String] the path, empty for a message-level rule
    #: (untyped path, Google::Protobuf::_MessageClass message_class, ?json_names: bool) -> String
    def self.render(path, message_class, json_names: false)
      return "" if path.nil?

      descriptor = message_class.descriptor #: untyped
      path.elements.map do |element|
        field = descriptor&.lookup(element.field_name)
        descriptor = field&.subtype
        "#{publish(field, element, json_names:)}#{subscript(element)}"
      end.join(".")
    end

    # @return [String] the name this segment is published under
    #: (untyped field, untyped element, json_names: bool) -> String
    def self.publish(field, element, json_names:)
      # A path segment the descriptor cannot resolve is published as the violation spelled it,
      # which is better than dropping the segment and renumbering the rest of the path.
      return element.field_name if field.nil?

      json_names ? field.json_name : field.name
    end

    # @return [String] the `[...]` suffix for a repeated or map element, empty otherwise
    #: (untyped element) -> String
    def self.subscript(element)
      case element.subscript
      when :index then "[#{element.index}]"
      when :bool_key then "[#{element.bool_key}]"
      when :int_key then "[#{element.int_key}]"
      when :uint_key then "[#{element.uint_key}]"
      when :string_key then "[#{element.string_key.inspect}]"
      else ""
      end
    end

    private_class_method :publish, :subscript
  end
end
