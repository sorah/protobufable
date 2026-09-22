# Design

Why this library is shaped the way it is. [README.md](README.md) covers using it. Extracted
from a production API, where most of these decisions were paid for once already.

## What belongs here

Three gems divide this space, and the boundaries are deliberate.

[problem](https://github.com/sorah/problem) owns RFC 9457: the document, the declaration on the
error class, the renderer, the exceptions app. protobufable adds a catalogue backed by a
protobuf enum and a way to carry protobuf messages in the document. It reimplements none of the
rest, and `Problem::Details`, `Problem::Rescuable` and the `problem+json` renderer are not
wrapped here.

[connect_rpc_rails](https://github.com/ivry-inc/connect_rpc_rails) owns the Connect protocol.
Connect defines its own error body, and the code determines the HTTP status, so an RFC 9457
document cannot be the response; the two catalogues are bridged rather than duplicated, through
`ConnectRpcRails::Error.code_for_http_status` and a `render_connect_error` override. That
bridge belongs in a controller concern in the application, or in that gem, not here.

protobufable owns what is left: the schema being the schema, in requests, columns, responses
and the error catalogue.

## Parsing through the body parser

`Protobufable::RequestParseable` replaces the `:json` entry in `ActionDispatch::Request`'s
parser table. The body is then decoded exactly once, by `decode_json`, into the class the action
declared, and a wrong type is a 400 before any application code runs.

`connect_rpc_rails` solves the same problem the other way, decoding in `process_action` and
assigning `request.request_parameters`. That suits a protocol that owns the whole request; it
does not suit a REST endpoint that should keep behaving like a Rails endpoint, where `params`
must stay filled so an existing `params[:name]` reader keeps working and an endpoint can be
moved over one at a time.

### Declarations on the class, not in a table

The original kept a process-wide hash keyed by `[controller_path, action]`, filled from
`method_added`. That table outlives a reload, keeps an entry for a renamed action, cannot
describe an anonymous controller, and collides when two controllers name an action the same.
Here the declarations are a `class_attribute`, and the parser reaches them through
`ActionDispatch::Request#controller_class`, which the request already resolves for routing.

### The message wrapper

Rails' parameter filtering works on hashes and cannot see inside a protobuf message. A message
left plainly in `params` would therefore be rendered whole by the log formatter, every field
included. The wrapper answers `[FILTERED]` to `as_json` and exposes nothing to `inspect`.

## Two encoding settings, pointing opposite ways

`emit_defaults` is off for responses and on for stored columns, on purpose.

A response wants to be small, and wants an absent `optional` field to stay distinguishable from
one set to its default, which is the answer to the usual objection that proto3 cannot express
absence. A stored document wants the opposite: a shape that does not depend on which fields
happened to be set, so that comparing a freshly loaded document against the message in memory
means something, and so that anything reading the column in SQL does not have to tell absent
from default.

`preserve_proto_fieldnames` is on everywhere. ProtoJSON defaults to lowerCamelCase; snake_case
matches the rest of a Rails API and the OpenAPI generated with `naming=proto`. Both settings are
one-way doors for clients, which is why neither is left to the default.

## A type, not a coder

`Protobufable::JsonType` is an `ActiveModel::Type::Value` reporting `:json`. A `serialize` coder
over a `text` column would encode and decode just as well and get none of the rest: Rails and
the adapter would not know the column is JSON, casting from a Hash would not happen, and dirty
tracking would compare encoded text. `changed_in_place?` compares decoded messages, because a
`jsonb` column hands back a canonicalized document whose key order need not match what
`encode_json` produced, which would otherwise read as a change on every load.

## The problem catalogue

`Problem::Detailable` documents an extension contract for exactly this: prepend a module to the
error class's singleton overriding `type` and `status`, and call `super` for a class the
catalogue does not cover. Its DESIGN.md lists five clauses that make it work, each of which
fails silently rather than loudly, so `spec/protobufable/problem_typeable_derivation_spec.rb`
pins them from this side too.

### Overriding a method, not configuring an object

Which enum, and which annotation, are overridable class methods:

```ruby
def self.problem_type_enum = "myapp.api.ProblemType"
def self.problem_type_annotation = "myapp.api.problem_type"
```

A configuration object would bless one catalogue shape, add global mutable state, and not
compose with inheritance. A method is inherited, so a base class declares it once and a second
catalogue in the same application is simply another base class. Nothing is registered anywhere,
and the catalogue is built on first use and memoized on the class that asked, so a reloaded or
anonymous class cannot read one built for a previous one.

Neither method has a default. Since no annotation is shipped (below), there is nothing to guess
at, and the raise names the method to override.

### Titles come from the identifier

The original keyed titles by the enum value name, which meant two values publishing one
identifier had two locale entries that a spec had to check were still saying the same thing.
`Problem::I18nable` already keys titles by the published identifier, so sharing an identifier
shares a title structurally. The spec, and the duplicated entries, are gone.

### A literal declaration still wins

`type` and `status` fall through to the literal DSL when the class set one, which is the rule
`Problem::I18nable` follows for titles. A codebase can then move onto a catalogue gradually
instead of all at once.

## The option number

A custom option's field number is a global namespace, registered in
[protocolbuffers/protobuf docs/options.md](https://github.com/protocolbuffers/protobuf/blob/main/docs/options.md).
protobufable claims **1376**, provisionally: the entry is not in the registry yet.

Until it is, nothing generated from `proto/protobufable/problem.proto` is shipped — no `_pb.rb`,
no importable annotation. A number that moves after release breaks every `.proto` that imported
it, and a number taken from the "internal use" range invites exactly the collision the registry
exists to prevent. The file is carried in the repository anyway, so that turning shipping on is
a one-line change, and so the README's copy-paste snippet has a single source of truth.

### One sub-message, not one number per property

The original spends two extension numbers, one for the identifier and one for the status, to
say one thing about a value. A sub-message spends one:

```proto
extend google.protobuf.EnumValueOptions {
  optional ProblemTypeOptions problem_type = 1376;
}
```

A third property later is then a field rather than another registry request. The split layout is
still readable, through `problem_uri_annotation` and `problem_status_annotation`, so a catalogue
that already shipped the other way can migrate without rewriting its enum. That pair is a
migration path, not a choice a new application makes, which is why it is marked `@api private`
and documented here rather than in the README.

## Flat constants

`Protobufable::Problem` and `Protobufable::Protovalidate` would shadow the top-level `Problem`
and `Protovalidate` from inside the namespace: every reference to the real gem would need a `::`
prefix, and a missing one would resolve to the wrong constant without an error. The files are
grouped (`lib/protobufable/problem/typeable.rb`) and the constants are flat
(`Protobufable::ProblemTypeable`).

Each mixin carries the layer it attaches to in its name — `RequestParseable` and
`RequestValidatable` are controller concerns, `ColumnValidatable` is an ActiveRecord one — so a
reader knows where it belongs without opening the file.

## Callback ordering

Rails appends a re-registered `before_action` to the end of the chain. `RequestValidatable`
therefore re-registers its callback when an action binds its `protobuf_body`, which moves it
behind the authentication and authorization callbacks the controller declares above the action.
Without that, an invalid body would be answered before an unauthenticated one, and the endpoint
would become an oracle for what a valid body looks like. A controller that skipped the callback
has no entry to move and is left alone.

## Field paths

A protobuf field has two published names: `preferred_language` in the binary encoding and in
ProtoJSON with `preserve_proto_fieldnames`, `preferredLanguage` without it. A field path that
names the wrong one is a path the client cannot follow. `Protobufable::FieldPath` resolves each
segment against the descriptor rather than interpolating the name the violation carried;
`Protovalidate::Violation#field_path` always uses the proto name, which is why this exists.

## googleapis descriptors

`RetryInfo` and `BadRequest` look their message classes up in the generated pool rather than
requiring them. `google.rpc.*` belongs to the application that generates googleapis alongside
its own protos, and a second copy of those descriptors in one process is a boot failure, not a
warning. The error names what to generate.

## Alba internals

The `with_protobuf` parity check reads Alba's `@_attributes` and `@_traits`, which are private
to Alba. There is no public way to ask a resource what it declares, and a trait is a block
rather than a list, so seeing what it adds means evaluating it against a throwaway subclass. An
Alba release can rename either ivar and the check would silently stop checking, so
`spec/protobufable/alba_binding_spec.rb` asserts both names against the installed version.

## Types

Signatures are `rbs-inline` annotations generated into `sig/generated`, checked in and verified
in CI, plus hand-written `sig/manual` for what RBS cannot infer: `class_attribute` accessors,
and the self-type interfaces that say what a concern's includer supplies.

`rbs/` is a local RBS collection source carrying google-protobuf's 4.x surface. The gem ships no
signatures, and ruby/gem_rbs_collection's entry stops at 3.22, whose non-generic `RepeatedField`
contradicts the signatures protovalidate ships. It has to be a collection source rather than a
`sig/manual` file, because a gem's own signatures are loaded as library RBS and cannot reference
a project signature.

`protoc --rbs_out` is not used. It emits `RepeatedField` with two type parameters, which agrees
with neither the collection nor protovalidate, and the Steepfile checks `lib` only, so the spec
fixtures need no signatures.

## Deliberately out of scope

- **RFC 9457 itself.** [problem](https://github.com/sorah/problem) owns it.
- **Connect and gRPC.** [connect_rpc_rails](https://github.com/ivry-inc/connect_rpc_rails) owns
  the protocol; bridging the two error shapes belongs on that side of the seam.
- **OpenAPI generation.** Post-processing a gnostic document is a build step over `.proto`
  sources, not a library that runs in a request.
- **Opaque page tokens.** A protobuf-backed cursor is a small thing to write and a large thing
  to make general.
- **`application/problem+xml`.**
