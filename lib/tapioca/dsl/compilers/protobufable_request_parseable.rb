# frozen_string_literal: true

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

return unless defined?(Protobufable::RequestParseable)

module Tapioca
  module Dsl
    module Compilers
      # Types `message` on each controller that declares `protobuf_body`, so an action reads the
      # decoded request body as its message class without a cast.
      #
      # A controller whose actions declare one class gets that class:
      #
      # ~~~rb
      # class WidgetsController < ApplicationController
      #   include Protobufable::RequestParseable
      #
      #   protobuf_body Api::CreateWidgetRequest
      #   def create; end
      # end
      # ~~~
      #
      # ~~~rbi
      # # widgets_controller.rbi
      # # typed: true
      # class WidgetsController
      #   sig { returns(::Api::CreateWidgetRequest) }
      #   def message; end
      # end
      # ~~~
      #
      # A controller whose actions declare different classes gets their union, which an action
      # narrows itself, for example with `#: self as WidgetsController & ...` or a cast.
      #: [ConstantType = Class[top]]
      class ProtobufableRequestParseable < Compiler
        # @override
        #: -> void
        def decorate
          root.create_path(constant) do |controller|
            controller.create_method("message", return_type: return_type)
          end
        end

        class << self
          # @override
          #: -> Enumerable[Module[top]]
          def gather_constants
            all_classes.select do |klass|
              klass < ::Protobufable::RequestParseable && !declared_classes(klass).empty?
            end
          end

          #: (Class[top] klass) -> Array[Module[top]]
          def declared_classes(klass)
            klass.protobuf_body_declarations.values.map(&:message_class).uniq
          end
        end

        #: -> String
        private def return_type
          names = self.class.declared_classes(constant).map { |klass| "::#{klass.name}" }.sort
          names.one? ? names.first : "T.any(#{names.join(", ")})"
        end
      end
    end
  end
end
