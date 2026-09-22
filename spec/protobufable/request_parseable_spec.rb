# frozen_string_literal: true

require "action_controller"

Protobufable.install!
ActionController::Base.logger = nil

# Named classes, because ActionController::Metal#action needs a controller_name and the
# declarations hang off the class itself.
class ParseableTestController < ActionController::API
  include Protobufable::RequestParseable

  protobuf_body Protobufable::Testing::V1::Dummy
  def create
    render(json: {
      greeting: message.greeting,
      count: message.has_count? ? message.count : nil,
      seconds: message.timestamp&.seconds,
      message_class: message.class.name,
      params_greeting: params[:greeting],
    })
  end

  protobuf_body Protobufable::Testing::V1::Dummy, ignore_unknown_fields: true
  def update
    render(json: {greeting: message.greeting})
  end

  def index
    render(json: {status: "ok", protobuf: params.key?(:_protobuf)})
  end
end

# Declares a different message for an action of the same name, which a process-wide table keyed
# by action would have collided on.
class OtherParseableTestController < ActionController::API
  include Protobufable::RequestParseable

  protobuf_body Protobufable::Testing::V1::CreateWidgetRequest
  def create
    render(json: {name: message.name, message_class: message.class.name})
  end
end

class InheritingParseableTestController < ParseableTestController; end

RSpec.describe(Protobufable::RequestParseable) do
  def post_json(controller, action, body, controller_name: nil)
    env = Rack::MockRequest.env_for(
      "/test",
      method: "POST",
      input: body,
      "CONTENT_TYPE" => "application/json",
    )
    env["action_dispatch.request.path_parameters"] = {
      controller: controller_name || controller.controller_path,
      action: action.to_s,
    }
    status, headers, body = controller.action(action).call(env)
    collected = +""
    body.each { |chunk| collected << chunk }
    [status, headers, collected]
  end

  def json_body(...) = JSON.parse(post_json(...).fetch(2))

  describe "parsing a JSON body as protobuf" do
    it "hands the action a typed message" do
      body = json_body(ParseableTestController, :create, %({"greeting":"Hello"}))

      expect(body["greeting"]).to eq("Hello")
      expect(body["message_class"]).to eq("Protobufable::Testing::V1::Dummy")
    end

    it "decodes a well-known type" do
      body = json_body(
        ParseableTestController, :create,
        %({"greeting":"x","timestamp":"2024-06-20T15:45:30Z"})
      )

      expect(body["seconds"]).to eq(Time.utc(2024, 6, 20, 15, 45, 30).to_i)
    end

    it "preserves field presence for an optional scalar" do
      absent = json_body(ParseableTestController, :create, %({"greeting":"x"}))
      present = json_body(ParseableTestController, :create, %({"greeting":"x","count":0}))

      expect(absent["count"]).to be_nil
      expect(present["count"]).to eq(0)
    end

    it "still fills params, so existing readers keep working" do
      body = json_body(ParseableTestController, :create, %({"greeting":"Hello"}))

      expect(body["params_greeting"]).to eq("Hello")
    end
  end

  describe "unknown fields" do
    it "rejects them by default, so a client typo is not silently dropped" do
      expect do
        post_json(ParseableTestController, :create, %({"greeting":"x","nope":1}))
      end.to raise_error(ActionDispatch::Http::Parameters::ParseError)
    end

    it "ignores them when the action opts in" do
      body = json_body(ParseableTestController, :update, %({"greeting":"Hi","nope":1}))

      expect(body["greeting"]).to eq("Hi")
    end
  end

  describe "an action that declared nothing" do
    it "is left alone" do
      status, _headers, body = post_json(ParseableTestController, :index, "{}")

      expect(status).to eq(200)
      expect(JSON.parse(body)).to eq({"status" => "ok", "protobuf" => false})
    end
  end

  describe "declarations per controller class" do
    it "keeps two controllers with the same action name apart" do
      body = json_body(OtherParseableTestController, :create, %({"name":"widget"}))

      expect(body["message_class"]).to eq("Protobufable::Testing::V1::CreateWidgetRequest")
    end

    it "is inherited by a subclass" do
      body = json_body(
        InheritingParseableTestController, :create, %({"greeting":"Hello"}),
        controller_name: "inheriting_parseable_test"
      )

      expect(body["greeting"]).to eq("Hello")
    end

    it "does not leak a declaration from a subclass back to its parent" do
      subclass = Class.new(ParseableTestController) do
        protobuf_body Protobufable::Testing::V1::CreateWidgetRequest
        def create = head(:ok)
      end

      expect(subclass.protobuf_body_declarations["create"].message_class)
        .to eq(Protobufable::Testing::V1::CreateWidgetRequest)
      expect(ParseableTestController.protobuf_body_declarations["create"].message_class)
        .to eq(Protobufable::Testing::V1::Dummy)
    end
  end

  describe Protobufable::RequestParseable::MessageWrapper do
    subject(:wrapper) do
      described_class.new(Protobufable::Testing::V1::Dummy.new(greeting: "s3cr3t"))
    end

    it "renders as a filtered placeholder rather than its contents" do
      expect(wrapper.as_json).to eq("[FILTERED]")
      expect(wrapper.to_json).not_to include("s3cr3t")
    end

    it "exposes nothing through inspect" do
      expect(wrapper.instance_variables_to_inspect).to be_empty
    end

    it "still hands back the message on request" do
      expect(wrapper.to_original_message.greeting).to eq("s3cr3t")
      expect(wrapper.to_protobuf.greeting).to eq("s3cr3t")
    end
  end
end
