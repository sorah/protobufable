# frozen_string_literal: true

target :lib do
  signature "sig/generated", "sig/manual"
  check "lib"

  # protoc output. Its signature is hand-written in sig/manual instead, because buf has no rbs
  # plugin and protoc's own --rbs_out contradicts the signatures protovalidate ships.
  ignore "lib/**/*_pb.rb"
end
