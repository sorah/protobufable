# protobufable: Protocol Buffers as the schema of record for a Rails API

`protobufable` makes generated protobuf message classes the shape of a Rails application's
data, on the way in and on the way out. A JSON request body is decoded straight into the
message its action declares, so a wrong type is a 400 before the action runs and the action
reads a typed object instead of `params`. A `jsonb` column holds a message whose shape is
declared in a `.proto`. Errors take their type and status from a protobuf enum. Responses are
encoded by the schema's own encoder.

Each piece is a mixin you opt into. The gem's only hard dependencies are `google-protobuf` and
Rails; the integrations with [problem](https://github.com/sorah/problem),
[protovalidate](https://github.com/sorah/protovalidate-rb),
[alba](https://github.com/okuramasafumi/alba) and
[connect_rpc_rails](https://github.com/ivry-inc/connect_rpc_rails) are separate `require`s,
and none of those gems is a dependency.

```ruby
class WidgetsController < ApplicationController
  include Protobufable::RequestParseable

  protobuf_body Api::CreateWidgetRequest
  def create
    widget = Widget.create!(name: message.name)
    render proto_json: Api::CreateWidgetResponse.new(widget: WidgetResource.new(widget).as_protobuf)
  end
end
```

```console
$ curl -sS -X POST -H 'Content-Type: application/json' -d '{"name": 42}' https://api.example.com/v1/widgets
HTTP/1.1 400 Bad Request
```

## Features

- **Type checking before the action.** `decode_json` rejects a wrong type or an unknown field,
  so a controller never validates what the schema already describes.
- **Messages in the database.** An `ActiveModel` type, not a `serialize` coder, so dirty
  tracking, casting and JSON columns all behave.
- **An error catalogue in the schema.** `type` and `status` come from an enum value's
  annotation, so two errors needing different statuses are different types.
- **Value rules in the schema too.** `buf.validate` rules run on requests and on stored columns.
- **One catalogue over REST and Connect.** A problem raised in a Connect RPC goes out as a
  Connect error carrying the same document, so a caller dispatches on the same `type`.
- **Serializers that cannot drift.** An Alba resource bound to a message fails at load time
  when the two disagree, rather than silently sending an empty field.
- **Typed.** RBS signatures ship with the gem, and the suite type checks under Steep.

## Requirements

Ruby 3.4 or later, Rails 7.1 or later, and `google-protobuf` 4.26 or later.

`Protobufable::Problem::Typeable` needs the `problem` gem, `Protobufable::RequestValidatable` and
`Protobufable::ColumnValidatable` need `protovalidate`, `Protobufable::AlbaBinding` needs
`alba`, and `Protobufable::Connect::ProblemRescuable` needs `problem` and `connect_rpc_rails`.
None is installed for you.

## Installation

```
bundle add protobufable
```

Rails wires itself up through a railtie, which registers the renderers and installs the request
body parser. Outside Rails, call `Protobufable.install!` at boot.

## Request bodies

Declare the message an action accepts, above the action:

```ruby
class WidgetsController < ApplicationController
  include Protobufable::RequestParseable

  protobuf_body Api::CreateWidgetRequest
  def create
    Widget.create!(name: message.name, tags: message.tags.to_a)
  end
end
```

`message` is the decoded message. `params` is still filled from it, so anything already reading
`params[:name]` keeps working and an endpoint can be moved over one at a time.

| option | default | meaning |
|---|---|---|
| `ignore_unknown_fields` | `false` | When true, a field the schema does not declare is dropped. Left false, it is a 400, so a client's typo is not a value that silently never arrives. |

The body is decoded once, by replacing the `:json` parser, so nothing parses the JSON twice.
The parsed message is held behind a wrapper that renders as `[FILTERED]`, because Rails'
parameter filtering cannot see inside a protobuf message and would otherwise log every field it
holds.

## Responses

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

### Bound Alba resources

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

## Messages in a column

```ruby
class Widget < ApplicationRecord
  attribute :settings, Protobufable::JsonType.new(Internal::WidgetSettings),
    default: -> { Internal::WidgetSettings.new }
end
```

The column is `json` or `jsonb`, and its shape is declared in a `.proto` rather than left to
whatever a Hash happened to hold.

| method | in | out |
|---|---|---|
| `deserialize` | the stored document | the message, or `nil` |
| `serialize` | a message | the document to store, or `nil` |
| `cast` | a message, String, Hash or `nil` | the message |
| `changed_in_place?` | the loaded document and the held message | whether they differ |
| `type` | — | `:json` |

Pass `nil_as_default: true` for a nullable column whose Ruby value is semantically non-null: a
null column then reads back as an empty message, while `nil` is still written as `NULL`.

Reads tolerate unknown fields, so a row written by a newer schema stays readable mid-deploy.
Writes emit defaults, so the stored shape does not depend on which fields were set — which is
what makes the `changed_in_place?` comparison meaningful, and spares anything reading the column
in SQL from telling absent from default.

## Errors

Built on [problem](https://github.com/sorah/problem), which owns RFC 9457 itself. This supplies
the catalogue: an enum whose values carry the identifier and status they publish.

The gem supplies the option message. Declare the extension that carries it in your own `.proto`,
with a field number of your own — see [Caveats](#caveats) for why that part is yours — and
annotate the enum:

```proto
import "google/protobuf/descriptor.proto";
import "protobufable/problem.proto";

extend google.protobuf.EnumValueOptions {
  optional protobufable.ProblemTypeOptions problem_type = 50001;
}

enum ProblemType {
  PROBLEM_TYPE_UNSPECIFIED = 0;
  PROBLEM_TYPE_NOT_FOUND = 1 [(problem_type) = {uri: "not-found", http_status: 404}];
  PROBLEM_TYPE_WIDGET_NOT_READY = 2 [(problem_type) = {uri: "widget-not-ready", http_status: 409}];
}
```

Point the base class at it, then declare a value per error:

```ruby
require "protobufable/problem"

module Errors
  class ApiError < StandardError
    include Protobufable::Problem::Typeable

    def self.problem_type_enum = "myapp.api.ProblemType"
    def self.problem_type_annotation = "myapp.api.problem_type"
  end

  class NotFound < ApiError
    problem_type :PROBLEM_TYPE_NOT_FOUND
  end
end

raise Errors::NotFound.new(detail: "no widget w_123")
```

A value the enum does not define, or one carrying no annotation, raises when the class is
defined, so a typo fails on boot rather than on the first request that reaches the error.

The status is a property of the problem type, not of the code path that raised it. Several
values may publish one identifier where telling them apart would leak something; because
`Problem::I18nable` keys titles by the identifier, such values share a title too, so the
distinction cannot come back through the title instead.

### An enum annotated one option per property

A catalogue whose values carry the identifier and the status as two separate options, rather
than one message, is read by overriding the other pair:

```ruby
class ApiError < StandardError
  include Protobufable::Problem::Typeable

  def self.problem_type_enum = "myapp.api.ProblemType"
  def self.problem_uri_annotation = "myapp.api.problem_uri"
  def self.problem_status_annotation = "myapp.api.http_status"
end
```

Both halves are required, and they replace `problem_type_annotation` rather than supplementing
it. Everything else behaves the same. This is for a schema that is already shaped that way; a
new catalogue should use the single option message, which spends one registered extension number
instead of two.

### Publishing the enum value

The enum is internal by default: RFC 9457 requires `type` to be a URI reference, so what goes
on the wire is the identifier the value publishes, and the value itself stays a server-side
label. An API that wants clients to dispatch on the value instead can publish it as an
extension member, in one mixin:

```ruby
module PublishesProblemType
  def problem_extensions = super.merge(problem_type: self.class.problem_type.to_s)
end

module Errors
  class ApiError < StandardError
    include Protobufable::Problem::Typeable
    include PublishesProblemType

    def self.problem_type_enum = "myapp.api.ProblemType"
    def self.problem_type_annotation = "myapp.api.problem_type"
  end
end
```

```json
{"type": "not-found", "title": "Not Found", "status": 404, "problem_type": "PROBLEM_TYPE_NOT_FOUND"}
```

Every class under that base publishes its own value, and `super.merge` means it composes with
`Problem::Information` and anything else contributing members.

> [!WARNING]
> This publishes the finer grain. If two values deliberately share an identifier because telling
> them apart would leak something, the extension hands the caller exactly that distinction back.
> Publish the value only when no pair in the catalogue is hiding one — or override
> `problem_extensions` on the classes that are.

The value is also permanent once published: renaming an enum value is then a breaking change for
clients, on top of the usual protobuf reasons to treat values as append-only.

### Machine-readable detail

RFC 9457 reserves `detail` for prose. Anything a client acts on goes in `information`, as packed
`google.protobuf.Any`:

```ruby
class InvalidWidget < Errors::ApiError
  include Protobufable::Problem::Information

  problem_type :PROBLEM_TYPE_BAD_REQUEST

  def initialize(violations:, message_class:, **kwargs)
    @violations = violations
    @message_class = message_class
    super(**kwargs)
  end

  def problem_information
    super + [Protobufable::BadRequest.for(@violations, @message_class, json_names: true)]
  end
end
```

```json
{"type": "bad-request", "status": 400, "information": [
  {"@type": "type.googleapis.com/google.rpc.BadRequest",
   "field_violations": [{"field": "name", "description": "must be at least 1 characters"}]}
]}
```

`Protobufable::Problem::RetryInfo` is the ready-made one: it publishes a `google.rpc.RetryInfo` alongside
the `Retry-After` header `Problem::RetryAfter` already sends, so a generic HTTP client and a
generated client get the same answer.

```ruby
class TooManyRequests < Errors::ApiError
  include Protobufable::Problem::RetryInfo

  problem_type :PROBLEM_TYPE_TOO_MANY_REQUESTS
end

raise TooManyRequests.new(retry_after: 30)
```

## Value validation

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
violations to `Protobufable::BadRequest`.

The validation callback runs *after* the callbacks declared above the action, so an
unauthenticated request is answered before an invalid one and the endpoint does not become an
oracle for what a valid body looks like. Opt an action out with
`skip_before_action :validate_protobuf_body!`.

The same rules run over `JsonType` columns before save, so they hold wherever a record is
written — application code, a seed, the console:

```ruby
class ApplicationRecord < ActiveRecord::Base
  include Protobufable::ColumnValidatable
end
```

Compile the rules at boot, so a CEL typo fails startup rather than the first request, and no
request pays the compilation:

```ruby
# config/initializers/protobufable.rb
Rails.application.config.after_initialize { Protovalidate.register_all }
```

### Field paths

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

## Connect RPC

[connect_rpc_rails](https://github.com/ivry-inc/connect_rpc_rails) serves Connect RPCs from
ActionController. Connect defines its own error body, and the Connect code decides the HTTP
status, so a problem cannot be answered as `application/problem+json` there.
`Protobufable::Connect::ProblemRescuable` answers it as a Connect error instead:

```ruby
require "protobufable/connect"

class WidgetsController < ActionController::API
  include ConnectRpcRails::Controller
  include Protobufable::Connect::ProblemRescuable

  connect_service "myapp.api.WidgetsService"

  def get_widget
    widget = Widget.find_by(id: connect_request.id)
    raise Errors::NotFound.new(detail: "no widget #{connect_request.id}") unless widget

    Api::GetWidgetResponse.new(widget: WidgetResource.new(widget).as_protobuf)
  end
end
```

```json
{"code": "not_found", "message": "no widget w_123",
 "details": [{"type": "protobufable.ProblemDetails", "value": "..."}]}
```

The code is read off the problem's status with `ConnectRpcRails::Error.code_for_http_status`,
and the message is the detail, or the title when there is none. The document travels as the
detail, `information` included, so a caller reads the same `type` it would over REST. The HTTP
status is the code's: a 422 problem goes out as 400 `invalid_argument`, while the document's
`status` still reads 422.

Include it after `ConnectRpcRails::Controller`. It is `Problem::Rescuable` with only the
rendering step replaced, so reporting, headers, `problem_for` and `around_problem_render`
behave as they do over REST.

The message is `protobufable.ProblemDetails`, shipped in `protobufable/problem_details.proto`.
`information` carries the error's `problem_information` messages, packed as they are; other
extension members have no slot in the message and are dropped. To reference the message from
your own schema, for an OpenAPI document say, vendor that file (see [Caveats](#caveats)). To
pack a message of your own instead, override `problem_message_for` in the controller:

```ruby
private def problem_message_for(problem, error)
  Api::ProblemDetails.new(type: problem.type, title: problem.title, status: problem.status)
end
```

Only a problem raised inside the controller is answered this way. An exception escaping before
dispatch reaches the exceptions app, which connect_rpc_rails answers from `rescue_responses`.

## Caveats

- **The extension is yours to declare, and the enum always will be.** The catalogue is your
  API's own vocabulary, so the gem cannot supply it, nor anything referencing it;
  `Problem::Typeable` reads whichever enum you point it at. It does supply the option message. The
  `extend` that carries it is still yours for now: extension field numbers are a global
  namespace registered in
  [protocolbuffers/protobuf](https://github.com/protocolbuffers/protobuf/blob/main/docs/options.md),
  protobufable claims 1376 but does not hold it, and an extension whose number can still move
  would break every `.proto` that imported it. Pick a number from the internal-use range
  (50000–99999) meanwhile.
- **Importing `protobufable/problem.proto` or `protobufable/problem_details.proto` means
  vendoring it.** The files ship in the gem, but buf and protoc resolve imports from your own
  module, not from a gem path, so copy them into your proto tree and generate from there. Then
  drop the generated `protobufable/*_pb.rb`, which the gem already loads: a duplicate
  descriptor is a boot failure, not a warning.
- **`google.rpc` descriptors are not shipped either.** `Problem::RetryInfo` and `BadRequest` look their
  message classes up in the pool, so generate `google/rpc/error_details.proto` alongside your
  own protos. A second copy of those descriptors in one process is a boot failure.
- **`AlbaBinding` reads Alba internals.** The parity check uses `@_attributes` and `@_traits`,
  which are private to Alba, so an Alba release can break it. A spec pins the assumption against
  the installed version.
- **`protovalidate` is a prerelease** (`0.1.0.beta3` at the time of writing).
- **`problem` is not on RubyGems yet**; track it from its repository.
- Editing a `.proto` does not hot-reload. `google-protobuf` raises on a duplicate descriptor
  definition, so the development loop is to restart on regeneration.

## Development

```
bundle install
bundle exec rake      # specs, then rbs and steep
bundle exec yard      # docs
hk check --all        # rubocop, actionlint, zizmor
mise run protoc       # regenerate the spec fixtures
```

## See also

- [DESIGN.md](DESIGN.md) for why the library is shaped this way.
- [problem](https://github.com/sorah/problem) for RFC 9457 itself, and
  [connect_rpc_rails](https://github.com/ivry-inc/connect_rpc_rails) for the Connect protocol.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sorah/protobufable.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT). Copyright (c) 2026 Sorah Fukumori.
