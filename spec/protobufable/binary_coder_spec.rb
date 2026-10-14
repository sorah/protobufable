# frozen_string_literal: true

require "protobufable/binary_coder"

RSpec.describe(Protobufable::BinaryCoder) do
  let(:message_class) { Protobufable::Testing::V1::Nested }
  let(:coder) { described_class.new(message_class) }

  describe "#load" do
    it "decodes stored bytes into a message" do
      expect(coder.load(message_class.encode(message_class.new(label: "hi")))).to eq(message_class.new(label: "hi"))
    end

    it "returns nil for a null column" do
      expect(coder.load(nil)).to be_nil
    end
  end

  describe "#dump" do
    it "encodes a message into binary wire format" do
      dumped = coder.dump(message_class.new(label: "hi"))

      expect(dumped.encoding).to eq(Encoding::ASCII_8BIT)
      expect(message_class.decode(dumped).label).to eq("hi")
    end

    it "returns nil for nil" do
      expect(coder.dump(nil)).to be_nil
    end
  end
end
