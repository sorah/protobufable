# frozen_string_literal: true

require "active_support/core_ext/time"
require "alba"
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

  describe "the alba initializer" do
    subject(:run) { described_class.initializers.find { |i| i.name == "protobufable.alba" }.run }

    before { Alba.reset! }
    after { Alba.reset! }

    it "registers the :timestamp type" do
      run

      expect(Alba.find_type(:timestamp).convert(Time.utc(2024).in_time_zone)).to be_instance_of(Time)
    end

    it "leaves a :timestamp type the application registered in place" do
      Alba.register_type(:timestamp, converter: ->(_) { :app })

      run

      expect { Alba.find_type(:timestamp).convert(Time.now) }.to raise_error(TypeError)
    end
  end

  it "classifies a broken validation rule as a 400" do
    expect(described_class.config.action_dispatch.rescue_responses)
      .to include("Protobufable::RequestValidatable::InvalidMessage" => :bad_request)
  end
end
