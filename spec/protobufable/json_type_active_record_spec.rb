# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table(:widgets, force: true) do |t|
    t.json(:settings)
    t.json(:optional_settings)
  end
end

# A named class rather than an anonymous one: ActiveRecord derives the table name and the
# attribute set from the constant, and stub_const cannot run before the examples start.
class JsonTypeWidget < ActiveRecord::Base
  self.table_name = "widgets"

  attribute :settings, Protobufable::JsonType.new(Protobufable::Testing::V1::Nested),
    default: -> { Protobufable::Testing::V1::Nested.new }
  attribute :optional_settings,
    Protobufable::JsonType.new(Protobufable::Testing::V1::Nested, nil_as_default: true)
end

# The unit spec covers the type's own methods; this one covers what only a real record shows:
# that Rails treats the attribute as JSON, tracks it dirty, and does not see a change where
# there is none.
RSpec.describe("Protobufable::JsonType on ActiveRecord") do
  let(:nested) { Protobufable::Testing::V1::Nested }

  after { JsonTypeWidget.delete_all }

  it "defaults a new record to an empty message rather than nil" do
    expect(JsonTypeWidget.new.settings).to eq(nested.new)
  end

  it "round trips a message through the column" do
    widget = JsonTypeWidget.create!(settings: nested.new(label: "hi"))

    expect(JsonTypeWidget.find(widget.id).settings.label).to eq("hi")
  end

  it "does not report a freshly loaded record as changed" do
    id = JsonTypeWidget.create!(settings: nested.new(label: "hi")).id
    reloaded = JsonTypeWidget.find(id)

    expect(reloaded.changed?).to be(false)
    expect(reloaded.changes).to be_empty
  end

  it "tracks an assignment as a change" do
    widget = JsonTypeWidget.create!(settings: nested.new(label: "hi"))
    widget.settings = nested.new(label: "bye")

    expect(widget.settings_changed?).to be(true)
  end

  it "accepts a Hash on assignment" do
    widget = JsonTypeWidget.create!(settings: {"label" => "hi"})

    expect(JsonTypeWidget.find(widget.id).settings.label).to eq("hi")
  end

  it "reads a null column back as an empty message under nil_as_default" do
    widget = JsonTypeWidget.create!(settings: nested.new)

    expect(JsonTypeWidget.find(widget.id).optional_settings).to eq(nested.new)
  end
end
