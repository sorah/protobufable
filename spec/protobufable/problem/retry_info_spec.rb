# frozen_string_literal: true

require "problem"
require "protobufable/problem"

RSpec.describe(Protobufable::Problem::RetryInfo) do
  let(:throttled) do
    Class.new(StandardError) do
      include Problem::Detailable
      include Protobufable::Problem::RetryInfo

      type "too-many-requests"
      status 429
      title "Try again in %{retry_after} seconds"
    end
  end

  it "publishes the wait as a google.rpc.RetryInfo" do
    expect(throttled.new(retry_after: 30).to_problem.to_h[:information]).to eq([
      {"@type" => "type.googleapis.com/google.rpc.RetryInfo", "retry_delay" => "30s"},
    ])
  end

  # Problem::RetryAfter's contributions have to survive, or a generic HTTP client loses the
  # only form it understands.
  it "still sends the Retry-After header" do
    expect(throttled.new(retry_after: 30).problem_headers).to eq({"Retry-After" => "30"})
  end

  it "still publishes the retry_after extension member" do
    expect(throttled.new(retry_after: 30).to_problem.to_h[:retry_after]).to eq(30)
  end

  it "still interpolates the wait into the title" do
    expect(throttled.new(retry_after: 30).to_problem.title).to eq("Try again in 30 seconds")
  end

  it "accepts a Time and publishes the seconds remaining" do
    information = throttled.new(retry_after: Time.now + 45).to_problem.to_h[:information]

    expect(information.first["retry_delay"]).to match(/\A4[45]s\z/)
  end

  it "publishes 0s rather than a negative wait for a deadline already passed" do
    information = throttled.new(retry_after: Time.now - 10).to_problem.to_h[:information]

    expect(information.first["retry_delay"]).to eq("0s")
  end

  it "composes with an occurrence that carries information of its own" do
    klass = Class.new(throttled) do
      def problem_information
        super + [Protobufable::Testing::V1::Nested.new(label: "quota")]
      end
    end

    expect(klass.new(retry_after: 5).to_problem.to_h[:information].length).to eq(2)
  end

  it "names what to generate when googleapis is missing from the pool" do
    allow(Google::Protobuf::DescriptorPool.generated_pool)
      .to receive(:lookup).with("google.rpc.RetryInfo").and_return(nil)

    expect { throttled.new(retry_after: 5).to_problem }
      .to raise_error(Protobufable::Error, %r{generate google/rpc/error_details\.proto})
  end
end
