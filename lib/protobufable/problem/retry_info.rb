# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "problem/retry_after"

require "protobufable"
require "protobufable/problem/information"

module Protobufable
  # Publishes a retry interval as a `google.rpc.RetryInfo` as well as a Retry-After header.
  #
  # Problem::RetryAfter already sends the header and a `retry_after` member, which a generic
  # HTTP client obeys. This adds the form a client generated from the same protos already knows
  # how to read, so the two kinds of caller get the same answer.
  #
  # @example
  #   class TooManyRequests < Errors::ApiError
  #     include Protobufable::RetryInfo
  #
  #     problem_type :PROBLEM_TYPE_TOO_MANY_REQUESTS
  #   end
  #
  #   raise TooManyRequests.new(retry_after: 30)
  #
  # `google.rpc` descriptors are not shipped with this gem: they belong to the app that
  # generates googleapis alongside its own protos. The message class is looked up when it is
  # first needed, and the error names what to generate if it is missing.
  #
  # @rbs module-self ::Problem::Detailable
  module RetryInfo
    include ::Problem::RetryAfter
    include ProblemInformation

    # The message this publishes.
    MESSAGE = "google.rpc.RetryInfo" #: String

    # @return [Array<Object>] the occurrence's messages, with the retry interval appended
    #: () -> Array[untyped]
    def problem_information
      super + [RetryInfo.message_for(retry_after_seconds)]
    end

    # @param seconds [Integer] the wait
    # @return [Object] a `google.rpc.RetryInfo` carrying it
    # @raise [Protobufable::Error] when googleapis has not been generated into the pool
    #: (Integer seconds) -> untyped
    def self.message_for(seconds)
      descriptor = Google::Protobuf::DescriptorPool.generated_pool.lookup(MESSAGE) or
        raise Protobufable::Error,
          "#{MESSAGE} is not in the descriptor pool; generate google/rpc/error_details.proto"

      descriptor.msgclass.new(
        retry_delay: Google::Protobuf::Duration.new(seconds: seconds),
      )
    end
  end
end
