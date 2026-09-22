# frozen_string_literal: true

require "problem"
require "protobufable/problem"

RSpec.describe(Protobufable::ProblemTypeable) do
  before { I18n.backend = I18n::Backend::Simple.new }

  # The catalogue the fixtures declare, in the shape the library recommends.
  def base_class
    Class.new(StandardError) do
      include Protobufable::ProblemTypeable

      def self.problem_type_enum = "protobufable.testing.v1.ProblemType"
      def self.problem_type_annotation = "protobufable.testing.v1.problem_type"
    end
  end

  describe "deriving from the catalogue" do
    subject(:error) { Class.new(base_class) { problem_type :PROBLEM_TYPE_NOT_FOUND } }

    it "publishes the identifier the value carries, not the value name" do
      expect(error.type).to eq("not-found")
    end

    it "takes the status from the value rather than the raise site" do
      expect(error.status).to eq(404)
    end

    it "reads back the declared value" do
      expect(error.problem_type).to eq(:PROBLEM_TYPE_NOT_FOUND)
    end

    it "renders as an RFC 9457 document" do
      I18n.backend.store_translations(:en, problem_details: {titles: {not_found: "Not Found"}})

      expect(error.new(detail: "no widget").to_problem.to_h)
        .to eq({type: "not-found", title: "Not Found", status: 404, detail: "no widget"})
    end
  end

  describe "values sharing an identifier" do
    let(:forbidden) { Class.new(base_class) { problem_type :PROBLEM_TYPE_FORBIDDEN } }
    let(:suspended) { Class.new(base_class) { problem_type :PROBLEM_TYPE_FORBIDDEN_SUSPENDED } }

    it "publishes one identifier and one status, so a caller cannot tell them apart" do
      expect(suspended.type).to eq(forbidden.type)
      expect(suspended.status).to eq(forbidden.status)
    end

    # Titles are keyed by the published identifier, so this holds structurally rather than by
    # two locale entries that have to be kept saying the same thing.
    it "publishes one title as well" do
      I18n.backend.store_translations(:en, problem_details: {titles: {forbidden: "Forbidden"}})

      expect(suspended.title).to eq(forbidden.title)
    end
  end

  describe "a literal declaration" do
    it "wins over the catalogue" do
      error = Class.new(base_class) do
        problem_type :PROBLEM_TYPE_NOT_FOUND
        status 418
      end

      expect(error.status).to eq(418)
      expect(error.type).to eq("not-found")
    end

    it "still works on a class that declares no value at all" do
      error = Class.new(base_class) do
        type "hand-written"
        status 400
      end

      expect(error.type).to eq("hand-written")
      expect(error.status).to eq(400)
    end
  end

  describe "inheritance" do
    it "is inherited by a subclass that declares nothing" do
      parent = Class.new(base_class) { problem_type :PROBLEM_TYPE_NOT_FOUND }
      child = Class.new(parent)

      expect(child.type).to eq("not-found")
      expect(child.status).to eq(404)
    end

    it "lets a subclass declare a different value without disturbing its parent" do
      parent = Class.new(base_class) { problem_type :PROBLEM_TYPE_NOT_FOUND }
      child = Class.new(parent) { problem_type :PROBLEM_TYPE_FORBIDDEN }

      expect(child.type).to eq("forbidden")
      expect(child.status).to eq(403)
      expect(parent.type).to eq("not-found")
      expect(parent.status).to eq(404)
    end
  end

  describe "declaration-time validation" do
    it "rejects a value the enum does not define" do
      expect { Class.new(base_class) { problem_type :PROBLEM_TYPE_NOPE } }
        .to raise_error(Protobufable::Error, /unknown or unannotated value PROBLEM_TYPE_NOPE/)
    end

    it "rejects the unannotated zero value" do
      expect { Class.new(base_class) { problem_type :PROBLEM_TYPE_UNSPECIFIED } }
        .to raise_error(Protobufable::Error, /unknown or unannotated/)
    end

    it "says which method to override when no enum is declared" do
      error = Class.new(StandardError) { include Protobufable::ProblemTypeable }

      expect { error.problem_type(:PROBLEM_TYPE_NOT_FOUND) }
        .to raise_error(Protobufable::Error, /declares no problem type enum/)
    end

    it "says which method to override when no annotation is declared" do
      error = Class.new(StandardError) do
        include Protobufable::ProblemTypeable
        def self.problem_type_enum = "protobufable.testing.v1.ProblemType"
      end

      expect { error.problem_type(:PROBLEM_TYPE_NOT_FOUND) }
        .to raise_error(Protobufable::Error, /declares no problem type annotation/)
    end

    it "reports an enum that is not in the pool" do
      error = Class.new(base_class) { def self.problem_type_enum = "nope.NotAnEnum" }

      expect { error.problem_type(:PROBLEM_TYPE_NOT_FOUND) }
        .to raise_error(Protobufable::Error, /is not in the descriptor pool/)
    end
  end

  describe "the split annotation migration knob" do
    def legacy_class
      Class.new(StandardError) do
        include Protobufable::ProblemTypeable

        def self.problem_type_enum = "protobufable.testing.v1.LegacyProblemType"
        def self.problem_uri_annotation = "protobufable.testing.v1.legacy_problem_uri"
        def self.problem_status_annotation = "protobufable.testing.v1.legacy_http_status"
      end
    end

    it "reads a catalogue that spends one option number per property" do
      error = Class.new(legacy_class) { problem_type :LEGACY_PROBLEM_TYPE_NOT_FOUND }

      expect(error.type).to eq("not-found")
      expect(error.status).to eq(404)
    end

    it "needs both halves, not one" do
      error = Class.new(StandardError) do
        include Protobufable::ProblemTypeable
        def self.problem_type_enum = "protobufable.testing.v1.LegacyProblemType"
        def self.problem_uri_annotation = "protobufable.testing.v1.legacy_problem_uri"
      end

      expect { error.problem_type(:LEGACY_PROBLEM_TYPE_NOT_FOUND) }
        .to raise_error(Protobufable::Error, /needs both/)
    end
  end
end
