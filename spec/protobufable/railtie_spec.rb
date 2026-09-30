# frozen_string_literal: true

require "rails"
require "protobufable/railtie"

# The rest of the suite calls Protobufable.install! directly, because nothing here boots Rails.
# This checks the one thing that only booting shows: that an application picks the install up
# without an initializer of its own.
RSpec.describe(Protobufable::Railtie) do
  it "registers an initializer that installs the gem" do
    initializer = described_class.initializers.find { |i| i.name == "protobufable.install" }

    expect(initializer).not_to be_nil
  end

  it "installs the renderers and the body parser when that initializer runs" do
    described_class.initializers.find { |i| i.name == "protobufable.install" }.run

    expect(Mime[:protobuf]).not_to be_nil
    expect(ActionDispatch::Request.ancestors)
      .to include(Protobufable::RequestParseable::RequestPatch)
  end

  it "classifies a broken validation rule as a 400" do
    expect(described_class.config.action_dispatch.rescue_responses)
      .to include("Protobufable::RequestValidatable::InvalidMessage" => :bad_request)
  end
end
