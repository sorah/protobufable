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
and the message class. The gem does not answer it; see
[Answering a broken rule](#answering-a-broken-rule).

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

## Answering a broken rule

No handler for `InvalidMessage` is registered, because the response belongs to the API: its
shape, the spelling of its field paths, and whether googleapis is generated. The railtie only
lists it in `rescue_responses` as `:bad_request`, so left unrescued it reaches the exceptions app
as a 400 with that app's generic body. Rescue it with an error type of your own, or with one from
the problem catalogue.

An error type of your own renders whatever the API already sends for a client error:

```ruby
class ApplicationController < ActionController::API
  rescue_from Protobufable::RequestValidatable::InvalidMessage do |error|
    render status: 400,
      proto_json: Protobufable::BadRequest.for(error.violations, error.message_class, json_names: true)
  end
end
```

```json
{"field_violations": [{"field": "name", "description": "must be at least 1 characters"}]}
```

A problem-based error is a catalogue entry carrying the violations, such as `InvalidRequest` in
[Machine-readable detail](errors.md#machine-readable-detail), handed to `Problem::Rescuable`:

```ruby
class ApplicationController < ActionController::API
  include Problem::Rescuable

  rescue_from Protobufable::RequestValidatable::InvalidMessage do |error|
    render_problem_detailable(
      InvalidRequest.new(violations: error.violations, message_class: error.message_class),
    )
  end
end
```

```json
{"type": "bad-request", "status": 400, "information": [
  {"@type": "type.googleapis.com/google.rpc.BadRequest",
   "field_violations": [{"field": "name", "description": "must be at least 1 characters"}]}
]}
```

Call `render_problem_detailable` rather than raising the problem: Rails does not rescue an
exception raised inside a `rescue_from` handler.

## Stored columns

The same rules run over [`JsonType` columns](columns.md) before save, so they hold wherever a
record is written — application code, a seed, the console. This is opted into on the model,
independently of `RequestValidatable`:

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
