# Value validation

Decoding rejects a wrong type. `buf.validate` rules add what the type cannot say:

```proto
message CreateWidgetRequest {
  string name = 1 [(buf.validate.field).string = {min_len: 1, max_len: 100}];
  repeated string tags = 2 [(buf.validate.field).repeated = {max_items: 8, unique: true}];
}
```

```ruby
require "protobufable/protovalidate"

class WidgetsController < ApplicationController
  include Protobufable::RequestValidatable   # brings RequestParseable

  protobuf_body Api::CreateWidgetRequest
  def create = ...
end
```

A broken rule raises `Protobufable::RequestValidatable::InvalidMessage`, carrying the violations
and the message class. Rescue it where the application turns errors into responses, and hand the
violations to `Protobufable::BadRequest`, as in
[Machine-readable detail](errors.md#machine-readable-detail).

The validation callback runs *after* the callbacks declared above the action, so an
unauthenticated request is answered before an invalid one and the endpoint does not become an
oracle for what a valid body looks like. Opt an action out with
`skip_before_action :validate_protobuf_body!`.

Compile the rules at boot, so a CEL typo fails startup rather than the first request, and no
request pays the compilation:

```ruby
# config/initializers/protobufable.rb
Rails.application.config.after_initialize { Protovalidate.register_all }
```

## Stored columns

The same rules run over [`JsonType` columns](columns.md) before save, so they hold wherever a
record is written — application code, a seed, the console:

```ruby
class ApplicationRecord < ActiveRecord::Base
  include Protobufable::ColumnValidatable
end
```

## Field paths

`Protobufable::FieldPath` renders a violation's path in the spelling the caller sent. A protobuf
field has two published names, and a client that reads lowerCamelCase ProtoJSON cannot find a
field named the other way, so each segment is resolved against the descriptor rather than taken
from the name the violation carried:

```ruby
Protobufable::FieldPath.render(violation.field, Api::CreateWidgetRequest)
#=> "parts[0].part_name"
Protobufable::FieldPath.render(violation.field, Api::CreateWidgetRequest, json_names: true)
#=> "parts[0].partName"
```

## Caveats

- **`google.rpc` descriptors are not shipped.** `BadRequest` looks `google.rpc.BadRequest` up in
  the pool; see [Errors](errors.md#caveats).
