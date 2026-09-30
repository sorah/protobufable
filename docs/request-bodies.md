# Request bodies

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

To check values as well as types, see [Value validation](validation.md).
