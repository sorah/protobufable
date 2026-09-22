# Changelog

## 0.1.0 - 2026-09-22

Initial release.

- `Protobufable::RequestParseable` decodes a JSON request body into the protobuf message an
  action declares with `protobuf_body`.
- `Protobufable::Renderers` answers with a message as ProtoJSON or binary protobuf.
- `Protobufable::JsonType` stores a message in a `json` or `jsonb` column.
- `Protobufable::ProblemTypeable` derives an RFC 9457 type and status from a protobuf enum, as
  a catalogue layer over the problem gem.
- `Protobufable::ProblemInformation` publishes protobuf messages in a problem document, and
  `Protobufable::RetryInfo` publishes a retry interval as a `google.rpc.RetryInfo`.
- `Protobufable::RequestValidatable` and `Protobufable::ColumnValidatable` enforce
  `buf.validate` rules on requests and on stored columns, with `Protobufable::FieldPath` and
  `Protobufable::BadRequest` reporting which fields failed.
- `Protobufable::AlbaBinding` binds an Alba resource to a message and checks their field parity
  at load time.
