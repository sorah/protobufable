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

Pass `preserve_proto_fieldnames: true` to write the `.proto` field names (`part_name`) rather
than their lowerCamelCase JSON names (`partName`), for a column read in SQL or by tools that use
the `.proto` spelling. Reads accept either, so switching an existing column needs no migration.

Reads tolerate unknown fields, so a row written by a newer schema stays readable mid-deploy.
Writes emit defaults, so the stored shape does not depend on which fields were set — which is
what makes the `changed_in_place?` comparison meaningful, and spares anything reading the column
in SQL from telling absent from default.

To run `buf.validate` rules over the column before save, see
[Value validation](validation.md#stored-columns).

## `text` and `binary` columns

A column that is not JSON to the database takes a `serialize` coder instead.

```ruby
class Credential < ApplicationRecord
  serialize :secret, coder: Protobufable::BinaryCoder.new(Internal::CredentialSecret)
  serialize :settings, coder: Protobufable::JsonCoder.new(Internal::WidgetSettings)
end
```

`BinaryCoder` stores the wire format, for a `binary` or `bytea` column or anything that holds
opaque bytes, such as a value encrypted before it is written. `JsonCoder` stores ProtoJSON in a
`text` column, reading and writing it as `JsonType` does, and takes the same
`preserve_proto_fieldnames:`. Neither casts from a Hash, and dirty tracking compares encoded
values. `ColumnValidatable` checks only `JsonType` columns.

`JsonCoder` does not work on a `json` or `jsonb` column. `serialize` layers a coder over the
column's own type, so the String the coder dumps is JSON-encoded a second time and stored as a
string literal, and a stored object reaches the coder already parsed into a Hash. `JsonCoder`
raises `Protobufable::Error` on the latter. Rails refuses only `coder: JSON` on such a column, so
nothing stops the declaration at boot.
