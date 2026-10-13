# frozen_string_literal: true

require "action_controller"
require "tapioca/internal"
require "tapioca/helpers/test/dsl_compiler"
require "tapioca/dsl/compilers/protobufable_request_parseable"

class SingleBodyCompilerTestController < ActionController::API
  include Protobufable::RequestParseable

  protobuf_body Protobufable::Testing::V1::Dummy
  def create; end

  protobuf_body Protobufable::Testing::V1::Dummy
  def update; end
end

class MixedBodyCompilerTestController < ActionController::API
  include Protobufable::RequestParseable

  protobuf_body Protobufable::Testing::V1::Dummy
  def create; end

  protobuf_body Protobufable::Testing::V1::CreateWidgetRequest
  def update; end
end

class NoBodyCompilerTestController < ActionController::API
  include Protobufable::RequestParseable

  def index; end
end

RSpec.describe(Tapioca::Dsl::Compilers::ProtobufableRequestParseable) do
  let(:context) { Tapioca::Helpers::Test::DslCompiler::CompilerContext.new(described_class) }

  it "gathers only controllers that declare a body" do
    expect(context.gathered_constants).to include("SingleBodyCompilerTestController", "MixedBodyCompilerTestController")
    expect(context.gathered_constants).not_to include("NoBodyCompilerTestController")
  end

  it "types message as the one class a controller declares" do
    expect(context.rbi_for(:SingleBodyCompilerTestController)).to eq(<<~RBI)
      # typed: strong

      class SingleBodyCompilerTestController
        sig { returns(::Protobufable::Testing::V1::Dummy) }
        def message; end
      end
    RBI
  end

  it "types message as the union when actions declare different classes" do
    expect(context.rbi_for(:MixedBodyCompilerTestController)).to eq(<<~RBI)
      # typed: strong

      class MixedBodyCompilerTestController
        sig { returns(T.any(::Protobufable::Testing::V1::CreateWidgetRequest, ::Protobufable::Testing::V1::Dummy)) }
        def message; end
      end
    RBI
  end
end
