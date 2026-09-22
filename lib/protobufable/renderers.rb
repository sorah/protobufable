# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "action_controller"

module Protobufable
  # The media types and renderers for answering with a protobuf message.
  #
  # @example Binary, for a client that asked for it
  #   render protobuf: Api::GetWidgetResponse.new(widget:)
  #
  # @example ProtoJSON, which is ordinary JSON a client needs to know nothing about
  #   render proto_json: Api::GetWidgetResponse.new(widget:)
  module Renderers
    # The media type the binary renderer answers with.
    CONTENT_TYPE = "application/protobuf" #: String

    # Registers the media type and both renderers. Idempotent, so a second host installing on
    # the same process is harmless.
    #
    # @return [void]
    #: () -> void
    def self.install!
      Mime::Type.register(CONTENT_TYPE, :protobuf) unless Mime[:protobuf]

      # `self` inside a renderer block is the controller, which RBS has no way to name.
      # steep:ignore:start
      ActionController::Renderers.add(:protobuf) do |message, _options|
        self.content_type = if message.is_a?(String)
          Protobufable::Renderers::CONTENT_TYPE
        else
          # The descriptor name tells a caller which message it received without having to
          # infer it from the endpoint.
          "#{Protobufable::Renderers::CONTENT_TYPE}; " \
            "proto=#{message.class.descriptor.name}"
        end
        # After content_type=, which re-applies the default charset.
        response.charset = false

        message.is_a?(String) ? message : message.class.encode(message)
      end

      ActionController::Renderers.add(:proto_json) do |message, _options|
        self.content_type = "application/json"
        message.class.encode_json(
          message,
          # ProtoJSON defaults to lowerCamelCase. snake_case matches what the rest of a Rails
          # API sends and what the generated OpenAPI describes, and it is a one-way door for
          # clients, so it is not left to chance.
          preserve_proto_fieldnames: true,
          # Responses stay small and an absent `optional` field stays distinguishable from one
          # set to its default. Stored columns take the opposite setting, deliberately; see
          # Protobufable::JsonType.
          emit_defaults: false,
        )
      end
      # steep:ignore:end
    end
  end
end
