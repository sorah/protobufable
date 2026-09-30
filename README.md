# protobufable: Protocol Buffers as the schema of record for a Rails API

`protobufable` makes generated protobuf message classes the shape of a Rails application's
data, on the way in and on the way out. A JSON request body is decoded straight into the
message its action declares, so a wrong type is a 400 before the action runs and the action
reads a typed object instead of `params`. A `jsonb` column holds a message whose shape is
declared in a `.proto`. Errors take their type and status from a protobuf enum. Responses are
encoded by the schema's own encoder.

Installing the gem switches on only the `proto_json` and `protobuf` renderers and the request
body parser, which leaves a request alone unless its action declares `protobuf_body`. Every other
piece is a concern you include into the classes that want it, and it acts on those classes only;
each section below starts from that setup. The gem's only hard dependencies are
`google-protobuf` and Rails; the integrations with [problem](https://github.com/sorah/problem),
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

### Request bodies

`protobuf_body` declares the message an action accepts. The JSON body is decoded into it before
the action runs, so a wrong type or an unknown field is a 400 and the action reads a typed
`message` instead of `params`. See [docs/request-bodies.md](docs/request-bodies.md).

```ruby
class WidgetsController < ApplicationController
  include Protobufable::RequestParseable

  protobuf_body Api::CreateWidgetRequest
  def create
    Widget.create!(name: message.name, tags: message.tags.to_a)
  end
end
```

### Responses

`render proto_json:` and `render protobuf:` encode a message with the schema's own encoder, in
any controller. An Alba resource bound to a message fails at load time when the two disagree,
rather than silently sending an empty field. See [docs/responses.md](docs/responses.md).

```ruby
require "protobufable/alba_binding"

class WidgetResource < ApplicationResource
  include Protobufable::AlbaBinding

  with_protobuf Api::Widget do   # raises at load time unless it matches Api::Widget
    attributes :id, :name
  end
end

render proto_json: Api::GetWidgetResponse.new(widget: WidgetResource.new(widget).as_protobuf)
```

### Messages in a column

`Protobufable::JsonType` keeps a message in a `json` or `jsonb` column, declared per attribute.
It is an `ActiveModel` type, not a `serialize` coder, so dirty tracking and casting behave. See
[docs/columns.md](docs/columns.md).

```ruby
class Widget < ApplicationRecord
  attribute :settings, Protobufable::JsonType.new(Internal::WidgetSettings),
    default: -> { Internal::WidgetSettings.new }
end
```

### Errors

An error catalogue in the schema, built on [problem](https://github.com/sorah/problem): `type`
and `status` come from an enum value's annotation, so two errors needing different statuses are
different types, and a typo in the catalogue fails on boot. See [docs/errors.md](docs/errors.md).

```proto
enum ProblemType {
  PROBLEM_TYPE_UNSPECIFIED = 0;
  PROBLEM_TYPE_NOT_FOUND = 1 [(problem_type) = {uri: "not-found", http_status: 404}];
}
```

```ruby
require "protobufable/problem"

class ApiError < StandardError
  include Protobufable::Problem::Typeable

  def self.problem_type_enum = "myapp.api.ProblemType"
  def self.problem_type_annotation = "myapp.api.problem_type"
end

class NotFound < ApiError
  problem_type :PROBLEM_TYPE_NOT_FOUND
end

class ApplicationController < ActionController::API
  include Problem::Rescuable   # from problem; renders them as application/problem+json
end

raise NotFound.new(detail: "no widget w_123")   # 404, "type": "not-found"
```

### Value validation

`buf.validate` rules run on request bodies and on stored columns, and violations are reported
with field paths in the spelling the caller sent. A broken rule raises `InvalidMessage`, which
the gem leaves to the application to answer: render an error type of your own, as below, or one
from the [problem catalogue](docs/errors.md). See [docs/validation.md](docs/validation.md).

```proto
message CreateWidgetRequest {
  string name = 1 [(buf.validate.field).string = {min_len: 1, max_len: 100}];
}
```

```ruby
rescue_from Protobufable::RequestValidatable::InvalidMessage do |error|
  render status: 400,
    proto_json: Protobufable::BadRequest.for(error.violations, error.message_class, json_names: true)
end
```

```json
{"field_violations": [{"field": "name", "description": "must be at least 1 characters"}]}
```

### Connect RPC

A problem raised in a Connect RPC goes out as a Connect error carrying the same document, so a
caller dispatches on the same `type` over REST and Connect. See [docs/connect.md](docs/connect.md).

```ruby
require "protobufable/connect"

class WidgetsController < ActionController::API
  include ConnectRpcRails::Controller
  include Protobufable::Connect::ProblemRescuable   # after ConnectRpcRails::Controller
end
```

```json
{"code": "not_found", "message": "no widget w_123",
 "details": [{"type": "protobufable.ProblemDetails", "value": "..."}]}
```

### Typed

RBS signatures ship with the gem, and the suite type checks under Steep.

## Requirements

- Ruby 3.4 or later
- Rails 7.1 or later
- `google-protobuf` 4.26 or later

Optional dependencies are not installed for you. Add the ones for the features you use:

- [problem](https://github.com/sorah/problem): [Errors](docs/errors.md) and [Connect RPC](docs/connect.md)
- [protovalidate](https://github.com/sorah/protovalidate-rb): [Value validation](docs/validation.md)
- [alba](https://github.com/okuramasafumi/alba): [bound Alba resources](docs/responses.md#bound-alba-resources)
- [connect_rpc_rails](https://github.com/ivry-inc/connect_rpc_rails): [Connect RPC](docs/connect.md)

## Installation

```
bundle add protobufable
```

Rails wires itself up through a railtie, which registers the renderers and installs the request
body parser. Outside Rails, call `Protobufable.install!` at boot.

## Caveats

- **`protovalidate` is a prerelease** (`0.1.0.beta3` at the time of writing).
- Editing a `.proto` does not hot-reload. `google-protobuf` raises on a duplicate descriptor
  definition, so the development loop is to restart on regeneration.

Caveats specific to a feature are on its page, such as vendoring the shipped `.proto` files in
[docs/errors.md](docs/errors.md#caveats).

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
