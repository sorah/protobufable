# Responses

```ruby
render proto_json: Api::GetWidgetResponse.new(widget:)   # application/json
render protobuf: Api::GetWidgetResponse.new(widget:)     # application/protobuf
```

`proto_json` sends ProtoJSON with `preserve_proto_fieldnames: true` and `emit_defaults: false`:
snake_case, matching the rest of a Rails API, and no key for a field that was never set, so an
absent `optional` field stays distinguishable from one set to its default. Both are one-way
doors for clients, which is why they are not left to chance.

`protobuf` sends binary, with the descriptor name in the content type
(`application/protobuf; proto=myapp.api.GetWidgetResponse`).

## Bound Alba resources

```ruby
class WidgetResource < ApplicationResource
  include Protobufable::AlbaBinding

  with_protobuf Api::Widget do
    attributes :id, :name
    attributes created_at: :timestamp
    one :owner, resource: OwnerResource
  end
end
```

`with_protobuf` checks both directions when the class loads: an attribute the message does not
declare, and a field no attribute produces, each raise there rather than at response time. Put
every attribute inside the block — the check runs when `with_protobuf` does, so anything
declared after it is never compared.

`attributes created_at: :timestamp` needs the converter, because a `google.protobuf.Timestamp`
field refuses the `ActiveSupport::TimeWithZone` an ActiveRecord column hands back:

```ruby
# config/initializers/protobufable.rb
Protobufable::AlbaBinding.register_timestamp_type!
```

`AlbaBinding` needs the [alba](https://github.com/okuramasafumi/alba) gem.

## Caveats

- **`AlbaBinding` reads Alba internals.** The parity check uses `@_attributes` and `@_traits`,
  which are private to Alba, so an Alba release can break it. A spec pins the assumption against
  the installed version.
