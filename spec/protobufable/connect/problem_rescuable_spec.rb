# frozen_string_literal: true

require "action_controller"
require "problem"
require "protobufable/connect"

RSpec.describe(Protobufable::Connect::ProblemRescuable) do
  let(:invalid_widget) do
    Class.new(StandardError) do
      include Problem::Detailable
      include Protobufable::Problem::Information

      type "invalid-widget"
      status 422
      title "Invalid Widget"

      def problem_information
        super + [Protobufable::Testing::V1::Nested.new(label: "hi")]
      end
    end
  end

  let(:server_error) do
    Class.new(StandardError) do
      include Problem::Detailable

      type "internal"
      status 503
      title "Service Unavailable"
    end
  end

  before do
    ConnectRpcRails.install!
    stub_const("InvalidWidget", invalid_widget)
    stub_const("WidgetServerError", server_error)
  end

  def define_controller(name, parent: ActionController::API, &body)
    stub_const(name, Class.new(parent) do
      include ConnectRpcRails::Controller
      include Protobufable::Connect::ProblemRescuable

      connect_service "protobufable.testing.v1.WidgetsService"

      class_eval(&body)
    end)
  end

  def call_rpc(controller, body = {name: "gadget"})
    env = Rack::MockRequest.env_for(
      "/protobufable.testing.v1.WidgetsService/CreateWidget",
      method: "POST",
      input: JSON.generate(body),
      "CONTENT_TYPE" => "application/json",
    )
    status, headers, proxy = controller.action("create_widget").call(env)
    collected = +""
    proxy.each { |chunk| collected << chunk }
    [status, headers, JSON.parse(collected)]
  end

  def problem_detail(wire, message_class: Protobufable::ProblemDetails)
    detail = wire.fetch("details").first
    expect(detail.fetch("type")).to eq(message_class.descriptor.name)
    message_class.decode(detail.fetch("value").unpack1("m"))
  end

  it "answers with the Connect code for the problem's status" do
    controller = define_controller("WidgetsController") do
      def create_widget = raise(InvalidWidget.new(detail: "name is taken"))
    end

    status, headers, wire = call_rpc(controller)

    expect(status).to eq(400)
    expect(headers["content-type"]).to start_with("application/json")
    expect(wire).to include("code" => "invalid_argument", "message" => "name is taken")
  end

  it "keeps the problem's own status in the document" do
    controller = define_controller("WidgetsController") do
      def create_widget = raise(InvalidWidget)
    end

    _, _, wire = call_rpc(controller)

    expect(problem_detail(wire).to_h).to include(type: "invalid-widget", status: 422)
  end

  it "falls back on the title when the occurrence has no detail" do
    controller = define_controller("WidgetsController") do
      def create_widget = raise(InvalidWidget)
    end

    _, _, wire = call_rpc(controller)

    expect(wire.fetch("message")).to eq("Invalid Widget")
  end

  it "nests the information messages inside the document" do
    controller = define_controller("WidgetsController") do
      def create_widget = raise(InvalidWidget)
    end

    _, _, wire = call_rpc(controller)

    expect(wire.fetch("details").size).to eq(1)
    expect(problem_detail(wire).information.map { |any| any.unpack(Protobufable::Testing::V1::Nested) })
      .to eq([Protobufable::Testing::V1::Nested.new(label: "hi")])
  end

  it "carries every RFC 9457 member the problem has" do
    controller = define_controller("WidgetsController") do
      def create_widget = raise(InvalidWidget.new(detail: "name is taken"))

      private def problem_for(error) = error.to_problem.with(instance: "/widgets/w_1")
    end

    _, _, wire = call_rpc(controller)

    expect(problem_detail(wire)).to eq(Protobufable::ProblemDetails.new(
      type: "invalid-widget",
      title: "Invalid Widget",
      status: 422,
      detail: "name is taken",
      instance: "/widgets/w_1",
      information: [Google::Protobuf::Any.pack(Protobufable::Testing::V1::Nested.new(label: "hi"))],
    ))
  end

  it "drops extension members the message has no slot for" do
    tracked = Class.new(invalid_widget) do
      def problem_extensions = super.merge(request_id: "abc123")
    end
    stub_const("TrackedInvalidWidget", tracked)
    controller = define_controller("WidgetsController") do
      def create_widget = raise(TrackedInvalidWidget)
    end

    _, _, wire = call_rpc(controller)

    expect(problem_detail(wire).to_h.keys).to contain_exactly(:type, :title, :status, :information)
  end

  it "packs the message the controller builds" do
    controller = define_controller("WidgetsController") do
      def create_widget = raise(InvalidWidget)

      private def problem_message_for(problem, _error)
        Protobufable::Testing::V1::ApplicationProblemDetails.new(type: problem.type, status: problem.status)
      end
    end

    _, _, wire = call_rpc(controller)

    expect(problem_detail(wire, message_class: Protobufable::Testing::V1::ApplicationProblemDetails).to_h)
      .to eq({type: "invalid-widget", status: 422})
  end

  # ConnectRpcRails::Controller installs a handler per rescue_responses entry when it is included,
  # after anything the parent registered. An application that also registers its problems there,
  # for the exceptions app, would otherwise have them answered without the document.
  it "wins over a rescue_responses entry naming the same error" do
    ActionDispatch::ExceptionWrapper.rescue_responses["InvalidWidget"] = :conflict
    parent = Class.new(ActionController::API) { include Problem::Rescuable }
    controller = define_controller("WidgetsController", parent:) do
      def create_widget = raise(InvalidWidget)
    end

    _, headers, wire = call_rpc(controller)

    expect(headers["content-type"]).not_to include("problem+json")
    expect(wire.fetch("code")).to eq("invalid_argument")
    expect(problem_detail(wire).type).to eq("invalid-widget")
  ensure
    ActionDispatch::ExceptionWrapper.rescue_responses.delete("InvalidWidget")
  end

  it "reports a server-side problem through the Rails error reporter" do
    reported = []
    subscriber = Object.new
    subscriber.define_singleton_method(:report) { |error, **| reported << error }
    ActiveSupport.error_reporter.subscribe(subscriber)
    controller = define_controller("WidgetsController") do
      def create_widget = raise(WidgetServerError)
    end

    status, _, wire = call_rpc(controller)

    expect(status).to eq(503)
    expect(wire.fetch("code")).to eq("unavailable")
    expect(reported).to contain_exactly(an_instance_of(WidgetServerError))
  ensure
    ActiveSupport.error_reporter.unsubscribe(subscriber)
  end

  it "leaves a successful call alone" do
    controller = define_controller("WidgetsController") do
      def create_widget = Protobufable::Testing::V1::CreateWidgetResponse.new(id: "w_1")
    end

    status, _, wire = call_rpc(controller)

    expect(status).to eq(200)
    expect(wire).to eq({"id" => "w_1"})
  end
end
