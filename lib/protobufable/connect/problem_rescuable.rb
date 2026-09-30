# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "active_support/concern"
require "connect_rpc_rails"
require "problem"

require "protobufable"
require "protobufable/problem_details_pb"
require "protobufable/problem/information"

module Protobufable
  module Connect
    # Answers a ::Problem::Detailable raised in a Connect RPC as a Connect error rather than as
    # application/problem+json.
    #
    # The code is read off the problem's status and the message is its detail, or its title when
    # there is none. The document itself travels as a detail, so a caller dispatches on the same
    # `type` over Connect as over REST.
    #
    # @example
    #   class WidgetsController < ActionController::API
    #     include ConnectRpcRails::Controller
    #     include Protobufable::Connect::ProblemRescuable
    #
    #     connect_service "myapp.api.WidgetsService"
    #   end
    #
    # Include it after ConnectRpcRails::Controller. Only a problem raised inside the controller is
    # answered this way; one escaping before dispatch reaches the exceptions app.
    #
    # @rbs module-self _ProblemRescuableSelf
    module ProblemRescuable
      extend ActiveSupport::Concern

      include ::Problem::Rescuable

      # `self` inside an ActiveSupport::Concern block is the including class, which RBS has no
      # way to name.
      # steep:ignore:start
      included do
        # Registered again for a controller whose parent already included ::Problem::Rescuable, so
        # it follows the rescue_responses handlers ConnectRpcRails::Controller installed since:
        # Rails picks the most recently registered match.
        rescue_from(::Problem::Detailable, with: :render_problem_detailable)
      end
      # steep:ignore:end

      # Builds the message the document travels as. Override to build the application's own copy
      # of the message instead.
      #
      # `information` carries the error's {Problem::Information} messages, packed as they are rather
      # than re-read from the rendered document. Other extension members are dropped, because the
      # message has no slot for them.
      #
      # @param problem [::Problem::Details]
      # @param error [Exception] the error the document was built from
      # @return [Object] a protobuf message
      #: (::Problem::Details problem, untyped error) -> untyped
      private def problem_message_for(problem, error)
        information = [] #: Array[untyped]
        information = error.problem_information if error.is_a?(Protobufable::Problem::Information)

        ProblemDetails.new(
          type: problem.type || "",
          title: problem.title || "",
          status: problem.status,
          detail: problem.detail || "",
          instance: problem.instance || "",
          information: information.map { |info| Google::Protobuf::Any.pack(info) },
        )
      end

      # @param problem [::Problem::Details]
      # @param error [Exception]
      # @return [void]
      #: (::Problem::Details problem, untyped error) -> void
      private def render_problem(problem, error)
        render_connect_error(
          ConnectRpcRails::Error.new(
            ConnectRpcRails::Error.code_for_http_status(problem.status),
            problem.detail.presence || problem.title,
            details: [Google::Protobuf::Any.pack(problem_message_for(problem, error))],
          ),
        )
      end
    end
  end
end
