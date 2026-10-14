# frozen_string_literal: true

require "protobufable/json_coder"

RSpec.describe(Protobufable::JsonCoder) do
  let(:message_class) { Protobufable::Testing::V1::Nested }
  let(:coder) { described_class.new(message_class) }

  describe "#load" do
    it "decodes a stored document into a message" do
      expect(coder.load(%({"label":"hi"}))).to eq(message_class.new(label: "hi"))
    end

    it "returns nil for a null column" do
      expect(coder.load(nil)).to be_nil
    end

    it "tolerates a field written by a newer schema" do
      expect(coder.load(%({"label":"hi","future":1}))).to eq(message_class.new(label: "hi"))
    end

    it "refuses a document a json column has already parsed" do
      expect { coder.load({"label" => "hi"}) }.to raise_error(Protobufable::Error, /Protobufable::JsonType/)
    end
  end

  describe "#dump" do
    it "emits defaults, so the stored shape does not depend on what was set" do
      expect(coder.dump(message_class.new)).to eq(%({"label":""}))
    end

    it "returns nil for nil" do
      expect(coder.dump(nil)).to be_nil
    end

    context "with preserve_proto_fieldnames" do
      let(:coder) { described_class.new(Protobufable::Testing::V1::ValidatedPart, preserve_proto_fieldnames: true) }

      it "writes the .proto field names" do
        expect(coder.dump(Protobufable::Testing::V1::ValidatedPart.new(part_name: "a"))).to eq(%({"part_name":"a"}))
      end
    end
  end
end
