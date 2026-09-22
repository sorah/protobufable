# frozen_string_literal: true

require "action_controller"

Protobufable.install!

class RenderersTestController < ActionController::API
  def binary
    render(protobuf: Protobufable::Testing::V1::Nested.new(label: "hi"))
  end

  def binary_string
    render(protobuf: "already encoded")
  end

  def proto_json
    render(proto_json: Protobufable::Testing::V1::Dummy.new(greeting: "hi"))
  end

  def proto_json_snake_case
    render(proto_json: Protobufable::Testing::V1::CreateWidgetRequest.new(name: "w", tags: ["a"]))
  end
end

RSpec.describe(Protobufable::Renderers) do
  def call(action)
    env = Rack::MockRequest.env_for("/test", method: "GET")
    env["action_dispatch.request.path_parameters"] = {
      controller: "renderers_test",
      action: action.to_s,
    }
    status, headers, body = RenderersTestController.action(action).call(env)
    collected = +""
    body.each { |chunk| collected << chunk }
    [status, headers, collected]
  end

  it "registers the protobuf media type" do
    expect(Mime[:protobuf].to_s).to eq("application/protobuf")
  end

  describe "the protobuf renderer" do
    it "answers with the encoded message" do
      _status, _headers, body = call(:binary)

      expect(Protobufable::Testing::V1::Nested.decode(body).label).to eq("hi")
    end

    it "names the message in the content type, so a caller need not infer it" do
      _status, headers, _body = call(:binary)

      expect(headers["content-type"])
        .to eq("application/protobuf; proto=protobufable.testing.v1.Nested")
    end

    it "sets no charset on a binary body" do
      _status, headers, _body = call(:binary)

      expect(headers["content-type"]).not_to include("charset")
    end

    it "passes an already encoded String through" do
      _status, headers, body = call(:binary_string)

      expect(body).to eq("already encoded")
      expect(headers["content-type"]).to eq("application/protobuf")
    end
  end

  describe "the proto_json renderer" do
    it "answers with JSON" do
      _status, headers, body = call(:proto_json)

      expect(headers["content-type"]).to start_with("application/json")
      expect(JSON.parse(body)).to eq({"greeting" => "hi"})
    end

    it "omits defaults, keeping an absent optional field distinguishable" do
      _status, _headers, body = call(:proto_json)

      expect(JSON.parse(body)).not_to have_key("count")
      expect(JSON.parse(body)).not_to have_key("timestamp")
    end

    it "preserves proto field names rather than lowerCamelCasing them" do
      _status, _headers, body = call(:proto_json_snake_case)

      expect(JSON.parse(body)).to eq({"name" => "w", "tags" => ["a"]})
    end
  end
end
