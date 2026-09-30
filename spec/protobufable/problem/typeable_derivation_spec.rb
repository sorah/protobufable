# frozen_string_literal: true

require "problem"
require "protobufable/problem"

# Problem::Detailable's extension contract is what makes this layer work, and every clause of
# it fails silently rather than loudly: the derivation simply stops being consulted and every
# error publishes whatever the literal DSL held, which is usually nil. These pin it, so a
# refactor on either side of the seam breaks here rather than in production.
RSpec.describe("Protobufable::Problem::Typeable derivation") do
  def base_class
    Class.new(StandardError) do
      include Protobufable::Problem::Typeable

      def self.problem_type_enum = "protobufable.testing.v1.ProblemType"
      def self.problem_type_annotation = "protobufable.testing.v1.problem_type"
    end
  end

  it "puts the prepend ahead of the DSL it overrides" do
    klass = base_class
    ancestors = klass.singleton_class.ancestors

    expect(ancestors.index(Protobufable::Problem::Typeable::Derivation))
      .to be < ancestors.index(Problem::Detailable::ClassMethods)
  end

  it "reaches the DSL through self.class, not the class attributes behind it" do
    klass = Class.new(base_class) { problem_type :PROBLEM_TYPE_NOT_FOUND }

    # problem_uri is the attribute a literal `type` writes. Nothing wrote it here, so an
    # implementation reading it directly would publish nil.
    expect(klass.problem_uri).to be_nil
    expect(klass.new.to_problem.type).to eq("not-found")
  end

  it "keeps the interpolations keyword, which a title template is handed through" do
    parameters = Problem::Detailable::ClassMethods.instance_method(:title).parameters

    expect(parameters).to include([:key, :interpolations])
  end

  it "does not define type or status on the including class itself" do
    klass = base_class

    expect(klass.singleton_class.instance_methods(false)).not_to include(:type, :status)
  end

  # The trap: extending a ClassMethods onto a subclass puts it ahead of the prepend the
  # superclass holds, so a concern that mixes in a catalogue layer has to re-apply it.
  it "is re-applied on every inclusion, so a second concern cannot shadow it" do
    catalogue_concern = Module.new do
      extend ActiveSupport::Concern
      include Protobufable::Problem::Typeable
    end
    klass = Class.new(StandardError) do
      include catalogue_concern

      def self.problem_type_enum = "protobufable.testing.v1.ProblemType"
      def self.problem_type_annotation = "protobufable.testing.v1.problem_type"
      problem_type :PROBLEM_TYPE_FORBIDDEN
    end

    expect(klass.type).to eq("forbidden")
    expect(klass.status).to eq(403)
  end
end
