# frozen_string_literal: true

require "protobufable/problem"

# The message ships generated, but its RBS is hand-written, and the generation pipeline emits no
# signature to check it against. These pin the two together: a field renamed or retyped in the
# .proto fails here rather than in a consumer's type check.
RSpec.describe(Protobufable::ProblemTypeOptions) do
  let(:descriptor) { described_class.descriptor }

  it "is registered under the name an application imports" do
    expect(descriptor.name).to eq("protobufable.ProblemTypeOptions")
  end

  it "declares exactly the fields sig/manual/problem_pb.rbs does" do
    expect(descriptor.map { |field| [field.name, field.type] })
      .to contain_exactly(["uri", :string], ["http_status", :uint32])
  end

  it "carries what a problem type publishes" do
    options = described_class.new(uri: "not-found", http_status: 404)

    expect(options.uri).to eq("not-found")
    expect(options.http_status).to eq(404)
  end

  # It annotates enum values, so it must not depend on the enum it annotates, or the gem would
  # be shipping a guess at an application's catalogue.
  it "references nothing else" do
    expect(descriptor.to_proto.field.map(&:type_name).reject(&:empty?)).to be_empty
  end
end
