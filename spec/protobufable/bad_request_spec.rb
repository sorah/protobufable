# frozen_string_literal: true

require "protobufable/protovalidate"

RSpec.describe(Protobufable::BadRequest) do
  let(:request) { Protobufable::Testing::V1::CreateWidgetRequest }
  let(:message) { request.new(name: "", preferred_language: "x") }
  let(:violations) { Protovalidate.collect_violations(message) }

  it "builds one FieldViolation per violation" do
    expect(described_class.for(violations, request).field_violations.length).to eq(2)
  end

  it "carries the field, the description and the rule that produced it" do
    violation = described_class.for(violations, request).field_violations.first

    expect(violation.field).to eq("name")
    expect(violation.description).to include("at least 1 character")
    expect(violation.reason).to eq("string.min_len")
  end

  it "names fields as ProtoJSON spells them when asked" do
    fields = described_class.for(violations, request, json_names: true)
      .field_violations.map(&:field)

    expect(fields).to include("preferredLanguage")
  end

  it "names what to generate when googleapis is missing from the pool" do
    allow(Google::Protobuf::DescriptorPool.generated_pool)
      .to receive(:lookup).with("google.rpc.BadRequest").and_return(nil)

    expect { described_class.for(violations, request) }
      .to raise_error(Protobufable::Error, %r{generate google/rpc/error_details\.proto})
  end

  it "packs into a problem document through Problem::Information" do
    require "problem"
    require "protobufable/problem"

    klass = Class.new(StandardError) do
      include Problem::Detailable
      include Protobufable::Problem::Information

      type "bad-request"
      status 400
      title "Bad Request"
    end
    bad_request = described_class.for(violations, request, json_names: true)
    klass.define_method(:problem_information) { [bad_request] }

    information = klass.new.to_problem.to_h[:information].first
    expect(information["@type"]).to eq("type.googleapis.com/google.rpc.BadRequest")
    expect(information["field_violations"].map { |v| v["field"] }).to include("preferredLanguage")
  end
end
