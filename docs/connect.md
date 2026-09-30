# Connect RPC

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
your own schema, for an OpenAPI document say, vendor that file (see
[Errors: Caveats](errors.md#caveats)). To pack a message of your own instead, override
`problem_message_for` in the controller:

```ruby
private def problem_message_for(problem, error)
  Api::ProblemDetails.new(type: problem.type, title: problem.title, status: problem.status)
end
```

Only a problem raised inside the controller is answered this way. An exception escaping before
dispatch reaches the exceptions app, which connect_rpc_rails answers from `rescue_responses`.
