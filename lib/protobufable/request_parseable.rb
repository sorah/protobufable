# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "active_support/concern"
require "action_dispatch"

require "protobufable"

module Protobufable
  # Parses a JSON request body straight into a generated protobuf message, so a wrong type or
  # an unknown field is rejected before the action runs and the action reads a typed object
  # instead of `params`.
  #
  # The declaration sits above the action it describes, like a signature:
  #
  # @example
  #   class WidgetsController < ApplicationController
  #     include Protobufable::RequestParseable
  #
  #     protobuf_body Api::CreateWidgetRequest
  #     def create
  #       Widget.create!(name: message.name)
  #     end
  #   end
  #
  # {RequestPatch} has to be prepended to `ActionDispatch::Request` for any of this to happen;
  # {Protobufable.install!} does that, and the railtie calls it.
  #
  # @rbs module-self _RequestParseableSelf
  module RequestParseable
    extend ActiveSupport::Concern

    # What `protobuf_body` records about one action.
    Declaration = Data.define(:message_class, :ignore_unknown_fields)

    # Holds the parsed message in `params` without letting it be logged.
    #
    # Rails' parameter filtering cannot see inside a protobuf message, so a message reaching
    # the log formatter would print every field it holds, secrets included.
    class MessageWrapper
      # Stands in for the message wherever `params` is rendered.
      FILTERED = "[FILTERED]" #: String

      # @param message [Object] the parsed protobuf message
      # @return [void]
      #: (untyped message) -> void
      def initialize(message)
        @message = message
      end

      # @return [Array] always empty, so `inspect` does not reach the message
      #: () -> Array[Symbol]
      def instance_variables_to_inspect = []

      # The JSON log formatter renders payloads with ActiveSupport's `#to_json`, and
      # `Object#as_json` falls back to dumping instance variables.
      #
      # @return [String] {FILTERED}
      #: (*untyped) -> String
      def as_json(*) = FILTERED

      # @return [Object] the wrapped message
      #: () -> untyped
      def to_protobuf = to_original_message

      # @return [Object] the wrapped message
      #: () -> untyped
      def to_original_message
        @message
      end
    end

    # Replaces the `:json` body parser so the body is decoded once, into the declared class,
    # rather than parsed as JSON and then converted.
    module RequestPatch
      #: () -> Hash[Symbol, untyped]
      private def params_parsers
        original_parsers = super
        original_json_parser = original_parsers[Mime[:json].symbol]

        original_parsers.merge(
          Mime[:json].symbol => ->(raw_post) {
            RequestParseable.param_parser(self, raw_post, original_json_parser)
          },
        )
      end
    end

    # Decodes the body for a request whose action declared a message class, and falls through
    # to the original parser for every other request.
    #
    # The declaration is read off the controller class the request already resolves, rather
    # than a process-wide table keyed by controller path: a table outlives reloads and renames,
    # and cannot describe an anonymous controller at all.
    #
    # @param request [ActionDispatch::Request]
    # @param raw_post [String] the request body
    # @param original_parser [Proc] the parser this one stands in front of
    # @return [Hash] the request parameters, carrying the message under `:_protobuf`
    #: (untyped request, String raw_post, ^(String) -> untyped original_parser) -> untyped
    def self.param_parser(request, raw_post, original_parser)
      declaration = declaration_for(request)
      return original_parser.call(raw_post) unless declaration

      message = declaration.message_class.decode_json(
        raw_post,
        ignore_unknown_fields: declaration.ignore_unknown_fields,
      )
      message.to_h.merge(_protobuf: MessageWrapper.new(message))
    end

    # @param request [ActionDispatch::Request]
    # @return [Declaration, nil] what the routed action declared, if anything
    #: (untyped request) -> Declaration?
    def self.declaration_for(request)
      action = request.path_parameters[:action]
      return if action.nil?

      controller = request.controller_class
      return unless controller.respond_to?(:protobuf_body_declarations)

      controller.protobuf_body_declarations[action.to_s]
    rescue NameError
      # An unresolvable controller is not this parser's problem; routing reports it.
      nil
    end

    # `self` inside an ActiveSupport::Concern block is the including class, which RBS has no
    # way to name; the accessor this installs is declared in sig/manual instead.
    # steep:ignore:start
    included do
      class_attribute(:protobuf_body_declarations, default: {}.freeze, instance_accessor: false)
    end
    # steep:ignore:end

    # Class-level DSL installed by including the concern.
    #
    # @rbs module-self _RequestParseableClass
    module ClassMethods
      # Declares the message class the next action accepts.
      #
      # @param message_class [Class] the generated request message class
      # @param ignore_unknown_fields [Boolean] whether a field the schema does not declare is
      #   dropped rather than rejected. False by default, so a client's typo is a 400 rather
      #   than a value that silently never arrives.
      # @return [void]
      #: (Google::Protobuf::_MessageClass message_class, ?ignore_unknown_fields: bool) -> void
      def protobuf_body(message_class, ignore_unknown_fields: false)
        @next_protobuf_body = Declaration.new(message_class:, ignore_unknown_fields:)
        nil
      end

      # Binds a pending `protobuf_body` to the action defined under it.
      #
      # @param method_name [Symbol]
      # @return [void]
      #: (Symbol method_name) -> void
      def method_added(method_name)
        super
        declaration = @next_protobuf_body
        return unless declaration

        @next_protobuf_body = nil
        self.protobuf_body_declarations =
          protobuf_body_declarations.merge(method_name.to_s => declaration).freeze
      end
    end

    # @return [Object] the parsed message for this action
    # @raise [KeyError] when the action declared no message class
    #: () -> untyped
    def message
      params.fetch(:_protobuf).to_original_message
    end
  end
end
