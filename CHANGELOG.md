# Changelog

## Unreleased

- `Protobufable::JsonCoder` and `Protobufable::BinaryCoder` are `serialize` coders keeping a
  message in a `text` column as ProtoJSON or in a `binary` column as wire format. A `json` or
  `jsonb` column still takes `Protobufable::JsonType`; `JsonCoder` raises `Protobufable::Error`
  on a row such a column hands back parsed.
- The Railtie registers the Alba `:timestamp` type on boot when Alba is loaded, unless the
  application already registered a type by that name. Calling
  `Protobufable::AlbaBinding.register_timestamp_type!` from an initializer is no longer needed.

## 0.1.0 - 2026-10-13

Initial release.

- `Protobufable::RequestParseable` decodes a JSON request body into the protobuf message an
  action declares with `protobuf_body`. A request without a JSON body raises
  `ActionDispatch::Http::Parameters::ParseError` (a 400).
- A tapioca DSL compiler types `RequestParseable#message` on each controller declaring
  `protobuf_body`: the declared class, or the union of the classes its actions declare.
- `Protobufable::Renderers` answers with a message as ProtoJSON or binary protobuf.
- `Protobufable::JsonType` stores a message in a `json` or `jsonb` column, and with
  `preserve_proto_fieldnames:` writes the `.proto` field names instead of their lowerCamelCase
  JSON names.
- `Protobufable::Problem::Typeable` derives an RFC 9457 type and status from a protobuf enum, as
  a catalogue layer over the problem gem. The gem ships `protobufable.ProblemTypeOptions`, the
  message an enum value is annotated with; the extension carrying it is declared by the
  application.
- `Protobufable::Problem::Information` publishes protobuf messages in a problem document, and
  `Protobufable::Problem::RetryInfo` publishes a retry interval as a `google.rpc.RetryInfo`.
- `Protobufable::Connect::ProblemRescuable` (`require "protobufable/connect"`) answers a problem
  raised in a connect_rpc_rails controller as a Connect error carrying the document as a
  `protobufable.ProblemDetails`, shipped in `protobufable/problem_details.proto`.
- `Protobufable::RequestValidatable` and `Protobufable::ColumnValidatable` enforce
  `buf.validate` rules on requests and on stored columns, with `Protobufable::FieldPath` and
  `Protobufable::BadRequest` reporting which fields failed. The railtie lists
  `Protobufable::RequestValidatable::InvalidMessage` in `rescue_responses` as `:bad_request`.
- `Protobufable::AlbaBinding` binds an Alba resource to a message and checks their field parity
  at load time.
