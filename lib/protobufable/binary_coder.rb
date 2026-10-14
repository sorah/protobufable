# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "protobufable"

module Protobufable
  # A `serialize` coder storing a protobuf message as its binary wire format, for a `binary` or
  # `bytea` column.
  #
  # @example
  #   class Credential < ApplicationRecord
  #     serialize :secret, coder: Protobufable::BinaryCoder.new(Internal::CredentialSecret)
  #   end
  class BinaryCoder
    # @return [Class] the generated message class this column holds
    attr_reader :message_class #: Google::Protobuf::_MessageClass

    # @param message_class [Class] the generated message class this column holds
    # @return [void]
    #: (Google::Protobuf::_MessageClass message_class) -> void
    def initialize(message_class)
      @message_class = message_class
    end

    # @param bytes [String, nil] the stored bytes
    # @return [Object, nil] the decoded message, or nil for a null column
    #: (String? bytes) -> untyped
    def load(bytes)
      return if bytes.nil?

      @message_class.decode(bytes)
    end

    # @param message [Object, nil] the message to store
    # @return [String, nil] the encoded bytes, or nil
    #: (untyped message) -> String?
    def dump(message)
      return if message.nil?

      @message_class.encode(message)
    end
  end
end
