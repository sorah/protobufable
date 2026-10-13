# Changelog

## Unreleased

- A tapioca DSL compiler types `RequestParseable#message` on each controller declaring
  `protobuf_body`: the declared class, or the union of the classes its actions declare.
- `RequestParseable#message` reads only the parsed body, so a `_protobuf` query parameter no longer
  stands in for the message (a 500), and a request without a JSON body raises
  `ActionDispatch::Http::Parameters::ParseError` (a 400).
- `Protobufable::JsonType` learns `preserve_proto_fieldnames:`, which writes the `.proto` field
  names instead of their lowerCamelCase JSON names.
- **Breaking:** the problem integration moves under `Protobufable::Problem`, matching its files:
  `Protobufable::ProblemTypeable` is now `Protobufable::Problem::Typeable`,
  `Protobufable::ProblemInformation` is `Protobufable::Problem::Information`, and
  `Protobufable::RetryInfo` is `Protobufable::Problem::RetryInfo`. `require "protobufable/problem"`
  is unchanged.
- `Protobufable::Connect::ProblemRescuable` (`require "protobufable/connect"`) answers a problem
  raised in a connect_rpc_rails controller as a Connect error carrying the document as a
  `protobufable.ProblemDetails`, shipped in `protobufable/problem_details.proto`.
- The railtie lists `Protobufable::RequestValidatable::InvalidMessage` in `rescue_responses` as
  `:bad_request`, so an unrescued broken rule is a 400 rather than a 500.

## 0.1.0 - 2026-09-22

Initial release.

- `Protobufable::RequestParseable` decodes a JSON request body into the protobuf message an
  action declares with `protobuf_body`.
- `Protobufable::Renderers` answers with a message as ProtoJSON or binary protobuf.
- `Protobufable::JsonType` stores a message in a `json` or `jsonb` column.
- `Protobufable::ProblemTypeable` derives an RFC 9457 type and status from a protobuf enum, as
  a catalogue layer over the problem gem. The gem ships `protobufable.ProblemTypeOptions`, the
  message an enum value is annotated with; the extension carrying it is declared by the
  application.
- `Protobufable::ProblemInformation` publishes protobuf messages in a problem document, and
  `Protobufable::RetryInfo` publishes a retry interval as a `google.rpc.RetryInfo`.
- `Protobufable::RequestValidatable` and `Protobufable::ColumnValidatable` enforce
  `buf.validate` rules on requests and on stored columns, with `Protobufable::FieldPath` and
  `Protobufable::BadRequest` reporting which fields failed.
- `Protobufable::AlbaBinding` binds an Alba resource to a message and checks their field parity
  at load time.
