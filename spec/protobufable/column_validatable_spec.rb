# frozen_string_literal: true

require "active_record"
require "protobufable/protovalidate"

ActiveRecord::Schema.define do
  create_table(:validated_widgets, force: true) do |t|
    t.json(:spec)
    t.json(:optional_spec)
  end
end

class ValidatedWidget < ActiveRecord::Base
  include Protobufable::ColumnValidatable

  self.table_name = "validated_widgets"

  attribute :spec, Protobufable::JsonType.new(Protobufable::Testing::V1::CreateWidgetRequest)
  attribute :optional_spec,
    Protobufable::JsonType.new(Protobufable::Testing::V1::CreateWidgetRequest)
end

RSpec.describe(Protobufable::ColumnValidatable) do
  let(:request) { Protobufable::Testing::V1::CreateWidgetRequest }

  def valid_spec(**overrides)
    request.new(name: "widget", preferred_language: "en", **overrides)
  end

  it "saves a record whose column satisfies the rules its .proto declares" do
    expect(ValidatedWidget.new(spec: valid_spec).valid?).to be(true)
  end

  it "refuses a record whose column breaks one, wherever it is written from" do
    widget = ValidatedWidget.new(spec: valid_spec(name: ""))

    expect(widget.valid?).to be(false)
    expect(widget.errors[:spec].join).to include("name: must be at least 1 character")
  end

  it "names the offending field, resolved through the descriptor" do
    widget = ValidatedWidget.new(spec: valid_spec(preferred_language: "x"))
    widget.valid?

    expect(widget.errors[:spec].join).to include("preferred_language: ")
  end

  it "names a nested field by its whole path" do
    widget = ValidatedWidget.new(spec: valid_spec(
      parts: [Protobufable::Testing::V1::ValidatedPart.new(part_name: "")],
    ))
    widget.valid?

    expect(widget.errors[:spec].join).to include("parts[0].part_name: ")
  end

  it "reports one error per violation" do
    widget = ValidatedWidget.new(spec: request.new)
    widget.valid?

    expect(widget.errors[:spec].length).to eq(2)
  end

  it "leaves a null column alone" do
    widget = ValidatedWidget.new(spec: valid_spec)

    expect(widget.optional_spec).to be_nil
    expect(widget.valid?).to be(true)
  end

  it "runs on save, not only on an explicit valid? call" do
    expect { ValidatedWidget.create!(spec: valid_spec(name: "")) }
      .to raise_error(ActiveRecord::RecordInvalid)
  end
end
