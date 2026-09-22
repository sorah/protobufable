# frozen_string_literal: true

require "action_controller"
require "protobufable/protovalidate"

Protobufable.install!

class ValidatableTestController < ActionController::API
  include Protobufable::RequestValidatable

  before_action :authenticate!

  protobuf_body Protobufable::Testing::V1::CreateWidgetRequest
  def create
    render(json: {name: message.name})
  end

  def index
    render(json: {status: "ok"})
  end

  class_attribute :authenticated, default: true

  private def authenticate!
    head(:unauthorized) unless self.class.authenticated
  end
end

class UnvalidatedTestController < ActionController::API
  include Protobufable::RequestValidatable
  skip_before_action :validate_protobuf_body!

  protobuf_body Protobufable::Testing::V1::CreateWidgetRequest
  def create
    render(json: {name: message.name})
  end
end

RSpec.describe(Protobufable::RequestValidatable) do
  def post_json(controller, action, body, controller_name:)
    env = Rack::MockRequest.env_for(
      "/test",
      method: "POST",
      input: body,
      "CONTENT_TYPE" => "application/json",
    )
    env["action_dispatch.request.path_parameters"] = {
      controller: controller_name,
      action: action.to_s,
    }
    status, _headers, response = controller.action(action).call(env)
    collected = +""
    response.each { |chunk| collected << chunk }
    [status, collected]
  end

  def post_valid(body, controller: ValidatableTestController, name: "validatable_test")
    post_json(controller, :create, body, controller_name: name)
  end

  it "lets a message that satisfies its rules through" do
    status, body = post_valid(%({"name":"widget","preferred_language":"en"}))

    expect(status).to eq(200)
    expect(JSON.parse(body)).to eq({"name" => "widget"})
  end

  it "raises when a rule is broken" do
    expect { post_valid(%({"name":"","preferred_language":"en"})) }
      .to raise_error(Protobufable::RequestValidatable::InvalidMessage, /min_len/)
  end

  it "carries the violations and the message class on the error" do
    post_valid(%({"name":"","preferred_language":"en"}))
  rescue Protobufable::RequestValidatable::InvalidMessage => e
    expect(e.violations.map(&:rule_id)).to include("string.min_len")
    expect(e.message_class).to eq(Protobufable::Testing::V1::CreateWidgetRequest)
  end

  it "leaves an action that declared no message alone" do
    status, body = post_json(ValidatableTestController, :index, "{}", controller_name: "validatable_test")

    expect(status).to eq(200)
    expect(JSON.parse(body)).to eq({"status" => "ok"})
  end

  it "can be skipped at the top of a controller" do
    status, body = post_valid(
      %({"name":""}),
      controller: UnvalidatedTestController,
      name: "unvalidated_test",
    )

    expect(status).to eq(200)
    expect(JSON.parse(body)).to eq({"name" => ""})
  end

  # The endpoint must not become an oracle for what a valid body looks like.
  describe "callback ordering" do
    around do |example|
      ValidatableTestController.authenticated = false
      example.run
    ensure
      ValidatableTestController.authenticated = true
    end

    it "answers an unauthenticated request before an invalid one" do
      status, _body = post_valid(%({"name":""}))

      expect(status).to eq(401)
    end
  end

  it "puts validation behind the callbacks declared above the action" do
    filters = ValidatableTestController._process_action_callbacks.map(&:filter)

    expect(filters.index(:validate_protobuf_body!)).to be > filters.index(:authenticate!)
  end
end
