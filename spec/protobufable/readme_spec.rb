# frozen_string_literal: true

require "problem"
require "protobufable/problem"
require "protobufable/protovalidate"

# The README makes claims about what the gem sends and refuses. These run them, so a change that
# makes the documentation wrong fails here.
RSpec.describe("README") do
  let(:request) { Protobufable::Testing::V1::CreateWidgetRequest }

  it "omits an unset optional field from a proto_json response" do
    encoded = Protobufable::Testing::V1::Dummy.encode_json(
      Protobufable::Testing::V1::Dummy.new(greeting: "hi"),
      preserve_proto_fieldnames: true,
      emit_defaults: false,
    )

    expect(JSON.parse(encoded)).to eq({"greeting" => "hi"})
  end

  it "emits defaults into a stored column, so the shape does not vary" do
    type = Protobufable::JsonType.new(Protobufable::Testing::V1::Nested)

    expect(type.serialize(Protobufable::Testing::V1::Nested.new)).to eq(%({"label":""}))
  end

  describe "the problem catalogue example" do
    let(:api_error) do
      Class.new(StandardError) do
        include Protobufable::ProblemTypeable

        def self.problem_type_enum = "protobufable.testing.v1.ProblemType"
        def self.problem_type_annotation = "protobufable.testing.v1.problem_type"
      end
    end

    before do
      I18n.backend = I18n::Backend::Simple.new
      I18n.backend.store_translations(:en, problem_details: {titles: {not_found: "Not Found"}})
    end

    it "publishes the annotated type and status" do
      not_found = Class.new(api_error) { problem_type :PROBLEM_TYPE_NOT_FOUND }

      expect(not_found.new(detail: "no widget w_123").to_problem.to_h).to eq({
        type: "not-found", title: "Not Found", status: 404, detail: "no widget w_123",
      })
    end

    it "fails when the class is defined, not when the error is raised" do
      expect { Class.new(api_error) { problem_type :PROBLEM_TYPE_TYPO } }
        .to raise_error(Protobufable::Error)
    end
  end

  describe "publishing the enum value as an extension" do
    let(:publishes_problem_type) do
      Module.new do
        def problem_extensions = super.merge(problem_type: self.class.problem_type.to_s)
      end
    end

    let(:api_error) do
      mixin = publishes_problem_type
      Class.new(StandardError) do
        include Protobufable::ProblemTypeable
        include mixin

        def self.problem_type_enum = "protobufable.testing.v1.ProblemType"
        def self.problem_type_annotation = "protobufable.testing.v1.problem_type"
      end
    end

    before do
      I18n.backend = I18n::Backend::Simple.new
      I18n.backend.store_translations(:en, problem_details: {titles: {not_found: "Not Found"}})
    end

    it "publishes the declared value alongside the RFC 9457 members" do
      not_found = Class.new(api_error) { problem_type :PROBLEM_TYPE_NOT_FOUND }

      expect(JSON.parse(not_found.new(detail: "no widget").to_problem.to_json)).to eq({
        "type" => "not-found",
        "title" => "Not Found",
        "status" => 404,
        "detail" => "no widget",
        "problem_type" => "PROBLEM_TYPE_NOT_FOUND",
      })
    end

    it "gives each subclass its own value" do
      not_found = Class.new(api_error) { problem_type :PROBLEM_TYPE_NOT_FOUND }
      forbidden = Class.new(api_error) { problem_type :PROBLEM_TYPE_FORBIDDEN }

      expect(not_found.new.problem_extensions[:problem_type]).to eq("PROBLEM_TYPE_NOT_FOUND")
      expect(forbidden.new.problem_extensions[:problem_type]).to eq("PROBLEM_TYPE_FORBIDDEN")
    end

    it "composes with ProblemInformation rather than replacing it" do
      klass = Class.new(api_error) do
        include Protobufable::ProblemInformation

        problem_type :PROBLEM_TYPE_NOT_FOUND

        def problem_information
          super + [Protobufable::Testing::V1::Nested.new(label: "hi")]
        end
      end

      expect(klass.new.problem_extensions.keys).to contain_exactly(:problem_type, :information)
    end

    # The warning the README carries: the extension is finer-grained than the identifier, so two
    # values sharing one to hide a distinction hand it back through this member.
    it "publishes the distinction a shared identifier hides" do
      forbidden = Class.new(api_error) { problem_type :PROBLEM_TYPE_FORBIDDEN }
      suspended = Class.new(api_error) { problem_type :PROBLEM_TYPE_FORBIDDEN_SUSPENDED }

      expect(suspended.type).to eq(forbidden.type)
      expect(suspended.new.problem_extensions[:problem_type])
        .not_to eq(forbidden.new.problem_extensions[:problem_type])
    end
  end

  it "publishes a BadRequest the way the README shows" do
    invalid = Class.new(StandardError) do
      include Problem::Detailable
      include Protobufable::ProblemInformation

      type "bad-request"
      status 400
      title "Bad Request"

      def initialize(violations:, message_class:, **kwargs)
        @violations = violations
        @message_class = message_class
        super(**kwargs)
      end

      def problem_information
        super + [Protobufable::BadRequest.for(@violations, @message_class, json_names: true)]
      end
    end
    message = Protobufable::Testing::V1::CreateWidgetRequest.new(name: "", preferred_language: "en")
    error = invalid.new(
      violations: Protovalidate.collect_violations(message),
      message_class: message.class,
    )

    document = error.to_problem.to_h
    expect(document[:type]).to eq("bad-request")
    expect(document[:information].first["@type"])
      .to eq("type.googleapis.com/google.rpc.BadRequest")
    expect(document[:information].first["field_violations"].first)
      .to include("field" => "name", "description" => "must be at least 1 characters")
  end

  it "publishes a retry interval in both forms" do
    throttled = Class.new(StandardError) do
      include Problem::Detailable
      include Protobufable::RetryInfo

      type "too-many-requests"
      status 429
      title "Too Many Requests"
    end
    error = throttled.new(retry_after: 30)

    expect(error.problem_headers).to eq({"Retry-After" => "30"})
    expect(error.to_problem.to_h[:information].first)
      .to eq({"@type" => "type.googleapis.com/google.rpc.RetryInfo", "retry_delay" => "30s"})
  end
end
