# frozen_string_literal: true

# Pins the fixture descriptors the rest of the suite builds on, so a regeneration that drops an
# annotation fails here rather than somewhere confusing.
RSpec.describe("spec fixtures") do
  let(:pool) { Google::Protobuf::DescriptorPool.generated_pool }

  it "registers the provisional problem_type option" do
    expect(pool.lookup("protobufable.testing.v1.problem_type")).not_to be_nil
  end

  it "annotates every catalogue value except the zero value" do
    values = pool.lookup("protobufable.testing.v1.ProblemType").to_proto.value
    annotation = pool.lookup("protobufable.testing.v1.problem_type")

    annotated = values.reject { |value| value.name.end_with?("_UNSPECIFIED") }
    expect(annotated).not_to be_empty
    annotated.each do |value|
      options = annotation.get(value.options)
      expect(options.uri).not_to be_empty
      expect(options.http_status).to be_positive
    end
  end

  it "keeps the legacy split annotations readable" do
    uri = pool.lookup("protobufable.testing.v1.legacy_problem_uri")
    status = pool.lookup("protobufable.testing.v1.legacy_http_status")
    value = pool.lookup("protobufable.testing.v1.LegacyProblemType").to_proto.value
      .find { |candidate| candidate.name == "LEGACY_PROBLEM_TYPE_NOT_FOUND" }

    expect(uri.get(value.options)).to eq("not-found")
    expect(status.get(value.options)).to eq(404)
  end

  it "decodes ProtoJSON with field presence" do
    dummy = Protobufable::Testing::V1::Dummy.decode_json(%({"greeting": "hi"}))

    expect(dummy.greeting).to eq("hi")
    expect(dummy.has_count?).to be(false)
  end
end
