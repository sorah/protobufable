# frozen_string_literal: true

require "protobufable/protovalidate"

RSpec.describe(Protobufable::FieldPath) do
  let(:request) { Protobufable::Testing::V1::CreateWidgetRequest }

  def path_for(message, json_names: false)
    Protovalidate.collect_violations(message).map do |violation|
      described_class.render(violation.field, message.class, json_names:)
    end
  end

  def valid(**overrides)
    request.new(name: "widget", preferred_language: "en", **overrides)
  end

  it "publishes the proto name by default" do
    expect(path_for(valid(preferred_language: "x"))).to eq(["preferred_language"])
  end

  # The two spellings are the whole point: a client that reads lowerCamelCase ProtoJSON cannot
  # find a field named the other way.
  it "publishes the json name when asked" do
    expect(path_for(valid(preferred_language: "x"), json_names: true)).to eq(["preferredLanguage"])
  end

  it "resolves each segment of a nested path through the descriptor" do
    message = valid(parts: [Protobufable::Testing::V1::ValidatedPart.new(part_name: "")])

    expect(path_for(message)).to eq(["parts[0].part_name"])
    expect(path_for(message, json_names: true)).to eq(["parts[0].partName"])
  end

  it "renders an empty path for a message-level rule" do
    expect(described_class.render(nil, request)).to eq("")
  end

  it "falls back to the name the violation carried for a segment it cannot resolve" do
    element = Buf::Validate::FieldPathElement.new(field_name: "not_a_field", field_number: 99)
    path = Buf::Validate::FieldPath.new(elements: [element])

    expect(described_class.render(path, request, json_names: true)).to eq("not_a_field")
  end
end
