# frozen_string_literal: true

require "problem"
require "protobufable/problem"

RSpec.describe(Protobufable::Problem::Information) do
  def error_class(&body)
    Class.new(StandardError) do
      include Problem::Detailable
      include Protobufable::Problem::Information

      type "invalid-widget"
      status 400
      title "Invalid Widget"

      class_eval(&body) if body
    end
  end

  it "publishes nothing when the occurrence carries no messages" do
    expect(error_class.new.to_problem.to_h).not_to have_key(:information)
  end

  it "publishes a packed message as ProtoJSON with its type URL" do
    klass = error_class do
      def problem_information
        super + [Protobufable::Testing::V1::Nested.new(label: "hi")]
      end
    end

    expect(klass.new.to_problem.to_h[:information]).to eq([
      {"@type" => "type.googleapis.com/protobufable.testing.v1.Nested", "label" => "hi"},
    ])
  end

  it "preserves proto field names, matching what the proto_json renderer sends" do
    klass = error_class do
      def problem_information
        super + [Google::Rpc::RetryInfo.new(
          retry_delay: Google::Protobuf::Duration.new(seconds: 30),
        )]
      end
    end

    expect(klass.new.to_problem.to_h[:information].first).to include("retry_delay" => "30s")
  end

  it "carries several messages in one member" do
    klass = error_class do
      def problem_information
        super + [
          Protobufable::Testing::V1::Nested.new(label: "a"),
          Protobufable::Testing::V1::Nested.new(label: "b"),
        ]
      end
    end

    expect(klass.new.to_problem.to_h[:information].map { |i| i["label"] }).to eq(["a", "b"])
  end

  it "composes with another mixin rather than clobbering it" do
    tracked = Module.new do
      def problem_extensions = super.merge(request_id: "abc123")
    end
    klass = Class.new(error_class do
      def problem_information
        super + [Protobufable::Testing::V1::Nested.new(label: "hi")]
      end
    end) { include tracked }

    expect(klass.new.problem_extensions.keys).to contain_exactly(:information, :request_id)
  end

  it "renders as JSON alongside the RFC 9457 members" do
    klass = error_class do
      def problem_information
        super + [Protobufable::Testing::V1::Nested.new(label: "hi")]
      end
    end

    expect(JSON.parse(klass.new(detail: "bad").to_problem.to_json)).to eq({
      "type" => "invalid-widget",
      "title" => "Invalid Widget",
      "status" => 400,
      "detail" => "bad",
      "information" => [
        {"@type" => "type.googleapis.com/protobufable.testing.v1.Nested", "label" => "hi"},
      ],
    })
  end
end
