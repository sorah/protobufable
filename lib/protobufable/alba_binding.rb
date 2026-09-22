# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "alba"

require "protobufable"

module Protobufable
  # Binds an Alba resource to the protobuf message it produces, and checks at load time that
  # the two agree on every field.
  #
  # Serialization stays idiomatic — one resource per model, with Alba's association DSL — while
  # the wire format belongs to the schema. The parity check is the point: without it a field
  # added to the .proto has no producer and simply comes back empty, which nothing reports.
  #
  # @example
  #   class WidgetResource < ApplicationResource
  #     with_protobuf Api::Widget do
  #       attributes :id, :name
  #       attribute(:created_at) { |w| w.created_at.to_time }
  #     end
  #   end
  #
  #   render proto_json: Api::GetWidgetResponse.new(widget: WidgetResource.new(widget).as_protobuf)
  #
  # The check reads Alba's `@_attributes` and `@_traits`, which are internal to Alba, so an
  # Alba release can break it. A spec pins the assumption against the installed version.
  #
  # @rbs module-self _AlbaBindingSelf
  module AlbaBinding
    # @param base [Class] the Alba resource class including this
    # @return [void]
    #: (untyped base) -> void
    def self.included(base)
      base.helper(HelperMethods)
    end

    # Each of these reaches the binding through `self.class`: Alba installs HelperMethods on
    # instances too, so a bare `message_class` here would resolve to the class-level reader with
    # `self` being the instance, whose ivar is never set.
    #
    # @return [Object] the bound message, built from the serialized attributes
    #: () -> untyped
    def as_protobuf = self.class.message_class.new(as_json)

    # @return [String] the bound message encoded as binary protobuf
    #: () -> String
    def to_protobuf = self.class.message_class.encode(as_protobuf)

    # Renders through the message's own encoder rather than Alba's, so the wire format is the
    # schema's. Field names and default omission match the proto_json renderer.
    #
    # @return [String] the bound message as ProtoJSON
    #: (*untyped) -> String
    def to_json(*)
      self.class.message_class
        .encode_json(as_protobuf, preserve_proto_fieldnames: true, emit_defaults: false)
    end

    # Class-level DSL, installed through Alba's own helper mechanism.
    #
    # @rbs module-self _AlbaBindingClass
    module HelperMethods
      # @return [Class] the message class this resource is bound to
      # @raise [Protobufable::Error] when the resource declared no binding
      #: () -> Google::Protobuf::_MessageClass
      def message_class
        @message_class || raise(
          Protobufable::Error,
          "#{name || self} is not bound to a message: declare one with `with_protobuf`",
        )
      end

      # Binds this resource to a message and declares its attributes.
      #
      # Both directions are checked: an attribute the message does not declare, and a field no
      # attribute produces, each fail here rather than at response time. The check runs when this
      # does, so an attribute declared after it is never compared; everything belongs inside the
      # block.
      #
      # @param klass [Class] the generated message class
      # @yield the resource's attribute declarations
      # @return [void]
      # @raise [Protobufable::Error] when the two have drifted apart
      #: (Google::Protobuf::_MessageClass klass) { () -> void } -> void
      def with_protobuf(klass, &block)
        module_eval(&block)
        @message_class = klass

        declared = klass.descriptor.map { |field| field.name.to_sym }
        produced = AlbaBinding.produced_attributes(self)

        unknown = declared - produced
        undeclared = produced - declared
        unless undeclared.empty?
          raise Protobufable::Error,
            "#{name} serializes #{undeclared.inspect}, which #{klass.name} does not declare"
        end
        unless unknown.empty?
          raise Protobufable::Error,
            "#{name} is missing #{unknown.inspect}, which #{klass.name} declares"
        end

        nil
      end
    end

    # Registers a `:timestamp` Alba type that converts to Time.
    #
    # A `google.protobuf.Timestamp` field accepts a Time but refuses an
    # ActiveSupport::TimeWithZone, which is what an ActiveRecord timestamp column hands back,
    # so a resource serializing one needs the conversion.
    #
    #   Protobufable::AlbaBinding.register_timestamp_type!
    #
    #   attribute :created_at, :timestamp
    #
    # Opt-in rather than done on require: Alba's type registry is global, and a gem should not
    # add to it behind a host's back.
    #
    # @return [void]
    #: () -> void
    def self.register_timestamp_type!
      Alba.register_type(:timestamp, converter: :to_time.to_proc, auto_convert: true)
      nil
    end

    # Every attribute a resource can produce, including the ones a trait adds.
    #
    # A trait is a block rather than a list, so the only way to see what it declares is to
    # evaluate it, which is what the throwaway subclass is for.
    #
    # @param resource [Class] the Alba resource
    # @return [Array<Symbol>]
    #: (untyped resource) -> Array[Symbol]
    def self.produced_attributes(resource)
      attributes = resource.instance_variable_get(:@_attributes).keys
      traits = resource.instance_variable_get(:@_traits) || {}

      attributes + traits.each_value.flat_map do |trait|
        Class.new(resource).tap { it.class_eval(&trait) }
          .instance_variable_get(:@_attributes).keys
      end
    end
  end
end
