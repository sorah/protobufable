# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "active_support/concern"
require "protovalidate"

require "protobufable"
require "protobufable/request_parseable"

module Protobufable
  # Runs the `buf.validate` rules of a `protobuf_body` message before the action does.
  #
  # Decoding already rejects a wrong type; this adds what the rules declare — lengths, formats,
  # ranges, cross-field conditions — so value validation lives in the schema next to the type
  # rather than in the controller.
  #
  # @example
  #   class WidgetsController < ApplicationController
  #     include Protobufable::RequestValidatable
  #
  #     protobuf_body Api::CreateWidgetRequest
  #     def create = ...
  #   end
  #
  # Raises {InvalidMessage}, which carries the violations. Rescue it wherever the application
  # turns errors into responses.
  #
  # @rbs module-self _RequestValidatableSelf
  module RequestValidatable
    extend ActiveSupport::Concern

    include RequestParseable

    # Raised when the request message breaks a rule its schema declares.
    class InvalidMessage < Protobufable::Error
      # @return [Array<Protovalidate::Violation>]
      attr_reader :violations #: Array[untyped]

      # @return [Class] the message the violations were produced from
      attr_reader :message_class #: Google::Protobuf::_MessageClass

      # @param violations [Array<Protovalidate::Violation>]
      # @param message_class [Class]
      # @return [void]
      #: (Array[untyped] violations, Google::Protobuf::_MessageClass message_class) -> void
      def initialize(violations, message_class)
        @violations = violations
        @message_class = message_class
        super(violations.map(&:to_s).join("; "))
      end
    end

    # `self` inside an ActiveSupport::Concern block is the including class, which RBS has no
    # way to name.
    # steep:ignore:start
    included do
      # Registered at include time so a controller can opt out at the top of the class with
      # `skip_before_action :validate_protobuf_body!`.
      before_action(:validate_protobuf_body!)
    end
    # steep:ignore:end

    # @rbs module-self _RequestValidatableClass
    module ClassMethods
      # Re-registers the validation callback behind the action's own declaration.
      #
      # Rails appends a re-registered callback to the end of the chain. Without this, the
      # callback stays where `included` put it — ahead of the authentication and authorization
      # callbacks a controller declares afterwards — and an invalid body would be answered
      # before an unauthenticated one, turning the endpoint into an oracle for what a valid
      # body looks like.
      #
      # A controller that skipped the callback has no entry to move, and is left alone.
      #
      # @param method_name [Symbol]
      # @return [void]
      #: (Symbol method_name) -> void
      def method_added(method_name)
        pending = protobuf_body_pending?
        super
        return unless pending
        return unless _process_action_callbacks.any? { |cb| cb.filter == :validate_protobuf_body! }

        before_action(:validate_protobuf_body!)
      end

      # @return [Boolean] whether a `protobuf_body` is waiting to bind to the next action
      #: () -> bool
      def protobuf_body_pending? = !instance_variable_get(:@next_protobuf_body).nil?
    end

    # Validates the parsed message, if this action declared one.
    #
    # @return [void]
    # @raise [InvalidMessage] when the message breaks a rule
    #: () -> void
    private def validate_protobuf_body!
      declaration = self.class.protobuf_body_declarations[action_name]
      return if declaration.nil?
      return unless params.key?(:_protobuf)

      violations = Protovalidate.collect_violations(message)
      return if violations.empty?

      raise InvalidMessage.new(violations, declaration.message_class)
    end
  end
end
