# frozen_string_literal: true

RSpec.describe(Protobufable::JsonType) do
  let(:message_class) { Protobufable::Testing::V1::Nested }
  let(:type) { described_class.new(message_class) }

  describe "#type" do
    it "is :json, so the adapter treats the column as JSON" do
      expect(type.type).to eq(:json)
    end
  end

  describe "#deserialize" do
    it "decodes a stored document into a message" do
      expect(type.deserialize(%({"label":"hi"}))).to eq(message_class.new(label: "hi"))
    end

    it "returns nil for a null column" do
      expect(type.deserialize(nil)).to be_nil
    end

    it "tolerates a field written by a newer schema" do
      expect(type.deserialize(%({"label":"hi","future":1}))).to eq(message_class.new(label: "hi"))
    end

    context "with nil_as_default" do
      let(:type) { described_class.new(message_class, nil_as_default: true) }

      it "reads a null column back as an empty message" do
        expect(type.deserialize(nil)).to eq(message_class.new)
      end
    end
  end

  describe "#serialize" do
    it "emits defaults, so the stored shape does not depend on what was set" do
      expect(type.serialize(message_class.new)).to eq(%({"label":""}))
    end

    it "returns nil for nil" do
      expect(type.serialize(nil)).to be_nil
    end

    context "with nil_as_default" do
      let(:type) { described_class.new(message_class, nil_as_default: true) }

      it "still writes nil rather than an empty document" do
        expect(type.serialize(nil)).to be_nil
      end
    end
  end

  describe "#cast" do
    it "passes a message through" do
      message = message_class.new(label: "hi")

      expect(type.cast(message)).to be(message)
    end

    it "casts a String" do
      expect(type.cast(%({"label":"hi"}))).to eq(message_class.new(label: "hi"))
    end

    it "casts a Hash, which is what a form or a seed supplies" do
      expect(type.cast({"label" => "hi"})).to eq(message_class.new(label: "hi"))
    end

    it "casts a Hash with symbol keys" do
      expect(type.cast({label: "hi"})).to eq(message_class.new(label: "hi"))
    end

    it "returns nil for nil" do
      expect(type.cast(nil)).to be_nil
    end

    it "leaves a value it does not recognise alone" do
      expect(type.cast(42)).to eq(42)
    end

    context "with nil_as_default" do
      let(:type) { described_class.new(message_class, nil_as_default: true) }

      it "casts nil to an empty message" do
        expect(type.cast(nil)).to eq(message_class.new)
      end
    end
  end

  describe "#changed_in_place?" do
    it "reports no change when a reordered document decodes to the same message" do
      reordered = %({"timestamp":null,"greeting":"hi"})
      type = described_class.new(Protobufable::Testing::V1::Dummy)

      expect(type.changed_in_place?(reordered, type.deserialize(reordered))).to be(false)
    end

    it "reports a change when the message differs" do
      expect(type.changed_in_place?(%({"label":"hi"}), message_class.new(label: "bye"))).to be(true)
    end
  end

  it "round trips through a store and a load" do
    message = message_class.new(label: "hi")

    expect(type.deserialize(type.serialize(message))).to eq(message)
  end
end
