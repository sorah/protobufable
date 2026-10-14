# frozen_string_literal: true

require "protobufable/binary_coder"
require "protobufable/json_coder"

ActiveRecord::Schema.define do
  create_table(:coded_widgets, force: true) do |t|
    t.binary(:secret)
    t.text(:settings)
    t.json(:json_settings)
  end
end

class CodedWidget < ActiveRecord::Base
  self.table_name = "coded_widgets"

  serialize :secret, coder: Protobufable::BinaryCoder.new(Protobufable::Testing::V1::Nested)
  serialize :settings, coder: Protobufable::JsonCoder.new(Protobufable::Testing::V1::Nested)
  serialize :json_settings, coder: Protobufable::JsonCoder.new(Protobufable::Testing::V1::Nested)
end

RSpec.describe("Protobufable coders on ActiveRecord") do
  let(:nested) { Protobufable::Testing::V1::Nested }

  after { CodedWidget.delete_all }

  it "round trips a message through a binary column" do
    widget = CodedWidget.create!(secret: nested.new(label: "hi"))

    expect(CodedWidget.find(widget.id).secret).to eq(nested.new(label: "hi"))
  end

  it "round trips a message through a text column" do
    widget = CodedWidget.create!(settings: nested.new(label: "hi"))

    expect(CodedWidget.find(widget.id).settings).to eq(nested.new(label: "hi"))
  end

  it "does not report a freshly loaded record as changed" do
    id = CodedWidget.create!(secret: nested.new(label: "a"), settings: nested.new(label: "b")).id

    expect(CodedWidget.find(id).changed?).to be(false)
  end

  describe "on a json column" do
    it "writes a JSON string literal rather than an object" do
      CodedWidget.create!(json_settings: nested.new(label: "hi"))

      expect(CodedWidget.connection.select_value("SELECT json_settings FROM coded_widgets"))
        .to eq(%("{\\"label\\":\\"hi\\"}"))
    end

    it "fails loudly on a row holding an object" do
      CodedWidget.connection.execute(%(INSERT INTO coded_widgets (json_settings) VALUES ('{"label":"hi"}')))

      expect { CodedWidget.last.json_settings }.to raise_error(Protobufable::Error)
    end
  end
end
