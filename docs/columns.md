# Messages in a column

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

To run `buf.validate` rules over the column before save, see
[Value validation](validation.md#stored-columns).
