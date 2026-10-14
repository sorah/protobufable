# frozen_string_literal: true

require "active_support/core_ext/time"

require "protobufable/alba_binding"

RSpec.describe(Protobufable::AlbaBinding) do
  let(:nested) { Protobufable::Testing::V1::Nested }
  let(:record) { Struct.new(:label, keyword_init: true) }

  def resource(&body)
    Class.new do
      include Alba::Resource
      include Protobufable::AlbaBinding

      class_eval(&body)
    end
  end

  describe "a bound resource" do
    subject(:klass) do
      resource do
        with_protobuf(Protobufable::Testing::V1::Nested) { attributes :label }
      end
    end

    it "builds the message it is bound to" do
      expect(klass.new(record.new(label: "hi")).as_protobuf).to eq(nested.new(label: "hi"))
    end

    it "encodes it as binary protobuf" do
      encoded = klass.new(record.new(label: "hi")).to_protobuf

      expect(nested.decode(encoded).label).to eq("hi")
    end

    it "renders through the message's own encoder rather than Alba's" do
      expect(klass.new(record.new(label: "hi")).to_json).to eq(%({"label":"hi"}))
    end

    it "omits defaults, matching the proto_json renderer" do
      expect(klass.new(record.new(label: "")).to_json).to eq("{}")
    end

    it "exposes the message class" do
      expect(klass.message_class).to eq(nested)
    end
  end

  describe "the parity check" do
    it "rejects an attribute the message does not declare" do
      expect do
        resource do
          with_protobuf(Protobufable::Testing::V1::Nested) { attributes :label, :extra }
        end
      end.to raise_error(Protobufable::Error, /serializes \[:extra\]/)
    end

    # The failure the check exists for: a field added to the .proto with no producer would
    # otherwise come back empty and nothing would report it.
    it "rejects a field no attribute produces" do
      expect do
        resource { with_protobuf(Protobufable::Testing::V1::Dummy) { attributes :greeting } }
      end.to raise_error(Protobufable::Error, /is missing/)
    end

    it "counts an attribute declared with a block" do
      klass = resource do
        with_protobuf(Protobufable::Testing::V1::Nested) do
          attribute(:label) { |object| object.label.upcase }
        end
      end

      expect(klass.new(Struct.new(:label).new("hi")).as_protobuf.label).to eq("HI")
    end

    it "counts the attributes a trait adds" do
      klass = resource do
        with_protobuf(Protobufable::Testing::V1::Nested) do
          trait(:extras) { attributes :label }
        end
      end

      expect(klass.message_class).to eq(nested)
    end

    it "sees an attribute declared before the block" do
      expect do
        resource do
          attributes :label
          with_protobuf(Protobufable::Testing::V1::Dummy) {}
        end
      end.to raise_error(Protobufable::Error, /serializes \[:label\]/)
    end

    # The check runs when with_protobuf does, so anything declared after it is never compared.
    # That is the reason to keep every attribute inside the block.
    it "cannot see an attribute declared after the block" do
      klass = resource do
        with_protobuf(Protobufable::Testing::V1::Nested) { attributes :label }
        attributes :extra
      end

      expect(klass.message_class).to eq(nested)
    end
  end

  describe "a nested message" do
    let(:nested_resource) do
      resource { with_protobuf(Protobufable::Testing::V1::Nested) { attributes :label } }
    end
    let(:part_resource) do
      resource { with_protobuf(Protobufable::Testing::V1::ValidatedPart) { attributes :part_name } }
    end
    let(:row) { Struct.new(:greeting, :count, :password, :timestamp, :nested, keyword_init: true) }

    it "builds a singular sub-message from a `one` association" do
      child = nested_resource
      klass = resource do
        with_protobuf(Protobufable::Testing::V1::Dummy) do
          attributes :greeting, :count, :password, :timestamp
          one :nested, resource: child
        end
      end

      message = klass.new(row.new(greeting: "hi", password: "", nested: record.new(label: "x")))
        .as_protobuf

      expect(message.nested).to eq(nested.new(label: "x"))
    end

    it "leaves the sub-message unset when the association is nil" do
      child = nested_resource
      klass = resource do
        with_protobuf(Protobufable::Testing::V1::Dummy) do
          attributes :greeting, :count, :password, :timestamp
          one :nested, resource: child
        end
      end

      message = klass.new(row.new(greeting: "hi", password: "")).as_protobuf

      expect(message.nested).to be_nil
    end

    it "builds a repeated sub-message from a `many` association" do
      part = part_resource
      klass = resource do
        with_protobuf(Protobufable::Testing::V1::CreateWidgetRequest) do
          attributes :name, :tags, :nested, :preferred_language
          many :parts, resource: part
        end
      end
      widget = Struct.new(:name, :tags, :nested, :preferred_language, :parts, keyword_init: true)
      part_row = Struct.new(:part_name)

      message = klass.new(widget.new(
        name: "w", tags: [], preferred_language: "en", parts: [part_row.new("a"), part_row.new("b")],
      )).as_protobuf

      expect(message.parts.map(&:part_name)).to eq(%w[a b])
    end

    # The parent counts the association as one attribute and never looks inside it.
    it "leaves an unbound association's fields unchecked until response time" do
      klass = resource do
        with_protobuf(Protobufable::Testing::V1::Dummy) do
          attributes :greeting, :count, :password, :timestamp
          one(:nested) { attributes :label, :extra }
        end
      end
      child = Struct.new(:label, :extra)

      expect { klass.new(row.new(greeting: "hi", password: "", nested: child.new("x", "y"))).as_protobuf }
        .to raise_error(ArgumentError, /extra/)
    end

    it "checks a bound association's resource against its own message" do
      expect do
        resource do
          with_protobuf(Protobufable::Testing::V1::Dummy) do
            attributes :greeting, :count, :password, :timestamp
            one :nested, resource: Class.new {
              include Alba::Resource
              include Protobufable::AlbaBinding

              with_protobuf(Protobufable::Testing::V1::Nested) { attributes :label, :extra }
            }
          end
        end
      end.to raise_error(Protobufable::Error, /serializes \[:extra\]/)
    end
  end

  it "says what to declare when a resource is bound to nothing" do
    klass = resource { attributes :label }

    expect { klass.message_class }
      .to raise_error(Protobufable::Error, /is not bound to a message/)
  end

  describe ".register_timestamp_type!" do
    before { described_class.register_timestamp_type! }

    # An ActiveRecord timestamp column hands back a TimeWithZone, which a Timestamp field
    # refuses outright.
    it "converts what a Timestamp field would otherwise refuse" do
      klass = resource do
        with_protobuf(Protobufable::Testing::V1::Dummy) do
          attributes :greeting, :count, :nested, :password, timestamp: :timestamp
        end
      end
      row = Struct.new(:greeting, :count, :nested, :password, :timestamp, keyword_init: true)
      zoned = Time.utc(2024, 6, 20, 15, 45, 30).in_time_zone("UTC")

      message = klass.new(row.new(
        greeting: "hi", count: nil, nested: nil, password: "", timestamp: zoned,
      )).as_protobuf

      expect(message.timestamp.to_time.utc).to eq(Time.utc(2024, 6, 20, 15, 45, 30))
    end
  end

  # Alba's @_attributes and @_traits are internal. If a release renames them the parity check
  # silently stops checking, so the assumption is pinned here rather than discovered later.
  it "reads the Alba internals the parity check depends on" do
    klass = resource do
      attributes :label
      trait(:extras) { attributes :label }
    end

    expect(klass.instance_variable_get(:@_attributes)).to eq({label: :label})
    expect(klass.instance_variable_get(:@_traits).keys).to eq([:extras])
  end
end
