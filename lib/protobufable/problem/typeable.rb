# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 Sorah Fukumori
# SPDX-License-Identifier: MIT

require "active_support/concern"
require "active_support/core_ext/class/attribute"
require "problem/i18nable"

require "protobufable"

module Protobufable
  module Problem
    # Derives an error's RFC 9457 type and status from a protobuf enum, whose values carry them
    # as a custom option.
    #
    # This is the catalogue layer ::Problem::Detailable documents: it prepends a module to the
    # error class's singleton that overrides `type` and `status`, and calls `super` for a class
    # the catalogue does not cover, so a literal declaration still works.
    #
    # Applications whose enum is annotated with one option per property override
    # {ClassMethods#problem_uri_annotation} and {ClassMethods#problem_status_annotation} instead.
    #
    # @example
    #   module Errors
    #     class ApiError < StandardError
    #       include Protobufable::Problem::Typeable
    #
    #       def self.problem_type_enum = "myapp.api.ProblemType"
    #       def self.problem_type_annotation = "myapp.api.problem_type"
    #     end
    #
    #     class WidgetNotReady < ApiError
    #       problem_type :PROBLEM_TYPE_WIDGET_NOT_READY
    #     end
    #   end
    #
    # The status is an annotation on the value rather than a property of the code path that
    # raised it: two errors needing different statuses are different types. Several values may
    # publish one identifier on purpose, where telling them apart would leak something; because
    # ::Problem::I18nable keys titles by the published identifier, they share a title too, which is
    # the invariant that keeps the distinction hidden.
    #
    # @rbs module-self ::Exception
    # @rbs module-self ::Problem::_DetailableSelf
    module Typeable
      extend ActiveSupport::Concern

      # Brings the DSL this overrides, and the title lookup, so one include covers all three.
      include ::Problem::I18nable

      # What one enum value publishes.
      Entry = Data.define(:uri, :http_status)

      # Overrides ::Problem::Detailable's literal DSL for a class that declared a value, and falls
      # through to it for one that did not.
      #
      # Prepended to the singleton class rather than defined in ClassMethods so it wins whichever
      # order the concerns were mixed in. A class that spells out a literal keeps it, the rule
      # ::Problem::I18nable already follows, so a codebase can move onto a catalogue gradually.
      #
      # @rbs module-self _TypeableClass
      module Derivation
        # The identifier the declared value publishes, which is its annotation rather than its
        # name: several values deliberately publish the same one.
        #
        # @param value [String, nil] a literal declaration, which takes precedence
        # @return [String, nil]
        #: (?String?) -> String?
        def type(value = nil)
          return super if value || problem_uri || problem_type.nil?

          @problem_type_uri ||= problem_type_entry.uri
        end

        # The status the declared value is returned with.
        #
        # @param value [Integer, nil] a literal declaration, which takes precedence
        # @return [Integer, nil]
        #: (?Integer?) -> Integer?
        def status(value = nil)
          return super if value || problem_status || problem_type.nil?

          @problem_type_status ||= problem_type_entry.http_status
        end
      end

      # `self` inside an ActiveSupport::Concern block is the including class, which RBS has no
      # way to name; the accessor this installs is declared in sig/manual instead.
      # steep:ignore:start
      included do
        class_attribute(:problem_type_value, instance_accessor: false)

        singleton_class.prepend(Derivation)
      end
      # steep:ignore:end

      # @rbs module-self _TypeableClass
      module ClassMethods
        # The full name of the enum this class's catalogue lives in.
        #
        # No default: an app's catalogue is the one thing a gem cannot guess. Override it on the
        # base class the rest of the errors inherit from.
        #
        # @return [String]
        # @raise [Protobufable::Error] when it has not been overridden
        #: () -> String
        def problem_type_enum
          raise Protobufable::Error,
            "#{name || self} declares no problem type enum: define " \
              "`def self.problem_type_enum` returning the full name of the enum its values live in"
        end

        # The full name of the extension carrying a value's uri and http_status as one message.
        #
        # No default either, because nothing generated from the gem's own .proto is shipped while
        # its option number is provisional. See DESIGN.md.
        #
        # @return [String]
        # @raise [Protobufable::Error] when neither this nor the split pair has been overridden
        #: () -> String
        def problem_type_annotation
          raise Protobufable::Error,
            "#{name || self} declares no problem type annotation: define " \
              "`def self.problem_type_annotation` returning the full name of the extension its " \
              "values are annotated with"
        end

        # The extension carrying a value's identifier, for a catalogue that spends one option
        # number per property rather than carrying both in one message.
        #
        # Override this and {problem_status_annotation} together, instead of
        # {problem_type_annotation}, when the enum is already annotated that way. An established
        # schema does not have to be rewritten to be read from here.
        #
        # @return [String, nil]
        #: () -> String?
        def problem_uri_annotation = nil

        # The extension carrying a value's status, alongside {problem_uri_annotation}.
        #
        # @return [String, nil]
        #: () -> String?
        def problem_status_annotation = nil

        # Declares which enum value this class renders as, or reads back what was declared.
        #
        # An unknown or unannotated value raises here, at class definition time, so a typo fails
        # on boot rather than on the first request that reaches the error.
        #
        # @param value [Symbol, nil] the enum value name
        # @return [Symbol, nil]
        # @raise [Protobufable::Error] when the catalogue does not cover the value
        #: (?Symbol?) -> Symbol?
        def problem_type(value = nil)
          return problem_type_value if value.nil?

          name = value.to_sym
          unless problem_type_catalogue.key?(name)
            raise Protobufable::Error,
              "unknown or unannotated value #{name} in #{problem_type_enum}"
          end

          self.problem_type_value = name
        end

        # The catalogue this class reads, built from the enum on first use.
        #
        # Memoized on the class that asked rather than in a table keyed by enum name: a reloaded
        # or anonymous class then cannot read a catalogue built for a previous one.
        #
        # @return [Hash{Symbol => Entry}]
        #: () -> Hash[Symbol, Entry]
        def problem_type_catalogue
          @problem_type_catalogue ||= Typeable.build_catalogue(
            enum: problem_type_enum,
            annotation: problem_uri_annotation ? nil : problem_type_annotation,
            uri_annotation: problem_uri_annotation,
            status_annotation: problem_status_annotation,
          )
        end

        # @return [Entry] what the declared value publishes
        #: () -> Entry
        def problem_type_entry = problem_type_catalogue.fetch(problem_type)
      end

      # Reads every annotated value of an enum.
      #
      # @param enum [String] full name of the enum
      # @param annotation [String, nil] full name of the single sub-message extension
      # @param uri_annotation [String, nil] full name of the identifier extension
      # @param status_annotation [String, nil] full name of the status extension
      # @return [Hash{Symbol => Entry}] one entry per value carrying both properties
      # @raise [Protobufable::Error] when a name does not resolve, or the split pair is half given
      #: (enum: String, annotation: String?, uri_annotation: String?, status_annotation: String?) -> Hash[Symbol, Entry]
      def self.build_catalogue(enum:, annotation:, uri_annotation:, status_annotation:)
        pool = Google::Protobuf::DescriptorPool.generated_pool
        descriptor = pool.lookup(enum) or
          raise Protobufable::Error, "enum #{enum} is not in the descriptor pool"

        readers = entry_readers(pool, annotation, uri_annotation, status_annotation)

        catalogue = {} #: Hash[Symbol, Entry]
        descriptor.to_proto.value.each do |value|
          options = value.options
          next if options.nil?

          entry = readers.call(options)
          next if entry.nil?

          catalogue[value.name.to_sym] = entry
        end
        catalogue.freeze
      end

      # @return [Proc] reads one value's options into an Entry, or nil when it carries none
      #: (untyped pool, String? annotation, String? uri_annotation, String? status_annotation) -> ^(untyped) -> Entry?
      def self.entry_readers(pool, annotation, uri_annotation, status_annotation)
        if uri_annotation || status_annotation
          unless uri_annotation && status_annotation
            raise Protobufable::Error,
              "a split annotation needs both problem_uri_annotation and problem_status_annotation"
          end

          uri = lookup_extension!(pool, uri_annotation)
          status = lookup_extension!(pool, status_annotation)
          return ->(options) {
            found = uri.get(options)
            code = status.get(options)
            next nil if found.nil? || found.empty? || code.nil? || code.zero?

            Entry.new(uri: found, http_status: code)
          }
        end

        extension = lookup_extension!(pool, annotation.to_s)
        ->(options) {
          found = extension.get(options)
          next nil if found.nil? || found.uri.empty? || found.http_status.zero?

          Entry.new(uri: found.uri, http_status: found.http_status)
        }
      end

      # @return [Google::Protobuf::FieldDescriptor]
      # @raise [Protobufable::Error] when the extension is not in the pool
      #: (untyped pool, String name) -> untyped
      def self.lookup_extension!(pool, name)
        pool.lookup(name) or
          raise Protobufable::Error,
            "extension #{name} is not in the descriptor pool; is its _pb.rb required?"
      end

      private_class_method :entry_readers, :lookup_extension!
    end
  end
end
