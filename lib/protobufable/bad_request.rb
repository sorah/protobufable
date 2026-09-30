# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "protobufable"
require "protobufable/field_path"

module Protobufable
  # Turns protovalidate violations into a `google.rpc.BadRequest`, the form AIP-193 defines for
  # telling a client which fields it got wrong.
  #
  # Hand the result to {Problem::Information}, which publishes it in the document.
  #
  # @example
  #   class InvalidMessage < Errors::BadRequest
  #     include Protobufable::Problem::Information
  #
  #     def initialize(violations:, **kwargs)
  #       @violations = violations
  #       super(**kwargs)
  #     end
  #
  #     def problem_information
  #       super + [Protobufable::BadRequest.for(@violations, message_class)]
  #     end
  #   end
  #
  # `google.rpc` descriptors are not shipped with this gem; the app that generates googleapis
  # alongside its own protos supplies them.
  module BadRequest
    # The message this builds.
    MESSAGE = "google.rpc.BadRequest" #: String

    # @param violations [Array<Protovalidate::Violation>]
    # @param message_class [Class] the message the violations were produced from
    # @param json_names [Boolean] whether field paths name fields as ProtoJSON spells them
    # @return [Object] a `google.rpc.BadRequest`, one FieldViolation per violation
    # @raise [Protobufable::Error] when googleapis has not been generated into the pool
    #: (Array[untyped] violations, Google::Protobuf::_MessageClass message_class, ?json_names: bool) -> untyped
    def self.for(violations, message_class, json_names: false)
      pool = Google::Protobuf::DescriptorPool.generated_pool
      bad_request = pool.lookup(MESSAGE) or
        raise Protobufable::Error,
          "#{MESSAGE} is not in the descriptor pool; generate google/rpc/error_details.proto"
      field_violation = pool.lookup("#{MESSAGE}.FieldViolation") #: untyped

      bad_request.msgclass.new(
        field_violations: violations.map do |violation|
          field_violation.msgclass.new(
            field: FieldPath.render(violation.field, message_class, json_names:),
            description: violation.message,
            reason: violation.rule_id,
          )
        end,
      )
    end
  end
end
