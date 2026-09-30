# frozen_string_literal: true

require "protobufable/problem_details_pb"

# The message ships generated, but its RBS is hand-written. These pin the two together, and pin
# the field layout an application copying the message has to match.
RSpec.describe(Protobufable::ProblemDetails) do
  let(:descriptor) { described_class.descriptor }

  it "is registered under the name an application imports" do
    expect(descriptor.name).to eq("protobufable.ProblemDetails")
  end

  it "declares exactly the fields sig/manual/problem_details_pb.rbs does" do
    expect(descriptor.map { |field| [field.name, field.type, field.label] }).to contain_exactly(
      ["type", :string, :optional],
      ["title", :string, :optional],
      ["status", :int32, :optional],
      ["detail", :string, :optional],
      ["instance", :string, :optional],
      ["information", :message, :repeated],
    )
  end

  # Anything referencing an application's catalogue would be a guess at somebody else's API.
  it "references nothing but google.protobuf.Any" do
    expect(descriptor.to_proto.field.map(&:type_name).reject(&:empty?))
      .to eq([".google.protobuf.Any"])
  end
end
