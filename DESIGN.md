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
`ConnectRpcRails::Error.code_for_http_status` and a `render_connect_error` call. That bridge
lives here, as an optional `require`, because what crosses it is the document as a protobuf
message, which is this gem's to build. The protocol itself stays on that side.

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
fails silently rather than loudly, so `spec/protobufable/problem/typeable_derivation_spec.rb`
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

### The enum stays off the wire

RFC 9457 requires `type` to be a URI reference, so the enum value cannot be it. That constraint
turns out to be useful: the enum can then be as fine-grained as the server needs for monitoring
while the response only distinguishes what a caller is allowed to distinguish, which is what
lets several values publish one identifier.

Nothing stops an application publishing the value anyway, as an extension member — the README
shows the mixin, and it is four lines. It is not shipped as a module because it is not a
default anyone should reach for without deciding: an API whose catalogue hides nothing loses
nothing by publishing the value, and an API with even one deliberately shared identifier hands
that distinction straight back. That is a judgement about a particular catalogue, not something
a gem can make.

### Titles come from the identifier

The original keyed titles by the enum value name, which meant two values publishing one
identifier had two locale entries that a spec had to check were still saying the same thing.
`Problem::I18nable` already keys titles by the published identifier, so sharing an identifier
shares a title structurally. The spec, and the duplicated entries, are gone.

### A literal declaration still wins

`type` and `status` fall through to the literal DSL when the class set one, which is the rule
`Problem::I18nable` follows for titles. A codebase can then move onto a catalogue gradually
instead of all at once.

## What a schema gem can and cannot ship

**The catalogue can never be shipped.** The enum is the list of problems one API can return: it
is the application's own vocabulary, and a gem that shipped one would be shipping a guess at
somebody else's API. Nor can anything referencing it — a message with a `ProblemType` field, a
`ProblemDetails` carrying one — which is the same guess one level removed. So the enum is named
by an overridable method and read through the descriptor pool, never through a generated
constant.

**The option message can, and does.** `protobufable.ProblemTypeOptions` says what a problem type
publishes — an identifier and a status — in the same shape for every application, and references
nothing. `proto/protobufable/problem.proto` holds exactly that, ships in the gem, and generates
`lib/protobufable/problem_pb.rb`.

**The document message can too.** `protobufable.ProblemDetails` carries the published `type`,
never the enum value, so it is RFC 9457's shape and nobody's catalogue. It sits in its own file,
`problem_details.proto`, because an application referencing it from its schema has to vendor
it, and should not have to vendor the option message along with it.

**The extension carrying it cannot ship yet**, and it is the only piece waiting on anything. An
extension's field number is a global namespace registered in
[protocolbuffers/protobuf docs/options.md](https://github.com/protocolbuffers/protobuf/blob/main/docs/options.md);
protobufable claims **1376**, provisionally, and does not hold it. A number that moved after
release would break every `.proto` that imported the extension, and one taken from the
internal-use range invites exactly the collision the registry exists to prevent. An application
therefore declares the `extend` itself, with a number of its own, over the message the gem
supplies:

```proto
import "google/protobuf/descriptor.proto";
import "protobufable/problem.proto";

extend google.protobuf.EnumValueOptions {
  optional protobufable.ProblemTypeOptions problem_type = 50001;
}
```

That is one line of schema rather than a copied message definition, and the shape stays the same
everywhere, which is what makes `problem_type_annotation` enough to point the catalogue at it.

### One sub-message, not one number per property

A catalogue could spend two extension numbers, one for the identifier and one for the status, to
say one thing about a value. Carrying both in one message spends one:

```proto
optional protobufable.ProblemTypeOptions problem_type = 50001;
```

A third property later is then a field on the message rather than another number, and a number
is the scarce thing. It is also why the message is worth shipping at all: were it two scalars,
there would be nothing generic left to ship.

The split layout is still readable, through `problem_uri_annotation` and
`problem_status_annotation`. An application whose enum is already annotated that way should not
have to rewrite its schema to be read from here, so those two are a supported extension point
rather than a hidden one — just not the shape a new catalogue should choose.

## Problems over Connect

### Built by the controller

The message the document travels as is built by `problem_message_for`, a controller method
beside `Problem::Rescuable`'s own `problem_for`. An application that declared its own copy of
the message, perhaps under its own package before this gem existed, overrides that one method,
and nothing is registered or configured anywhere.

### One detail, not one per message

The document goes out as a single Connect detail with `information` inside it, rather than
with each `information` message beside it as its own detail. A caller then reads one thing, in
the same shape it reads over REST, and a detail list does not grow a second copy of what the
document already carries.

### Only what the controller raises

`Connect::ProblemRescuable` is a `rescue_from`, so it sees what the controller raises and nothing
earlier. An exception escaping before dispatch reaches connect_rpc_rails' exceptions app, which
answers from `rescue_responses`. That keeps the exceptions app free of any knowledge of
problems, at the cost of a problem raised in middleware going out as whatever status its class
is registered with.

### Registered twice

`Problem::Rescuable` registers its handler when it is first included. A controller whose parent
already included it would keep that registration, which precedes the `rescue_responses`
handlers `ConnectRpcRails::Controller` installs, so a problem class an application also listed
in `rescue_responses` would be answered by the transport without its document.
`Connect::ProblemRescuable` registers the handler again to follow them.

## Constants and files

The problem integration lives under `Protobufable::Problem` and the Connect one under
`Protobufable::Connect`, one file per constant: `lib/protobufable/problem/typeable.rb` defines
`Protobufable::Problem::Typeable`. Inside `Protobufable` a bare `Problem` resolves to
`Protobufable::Problem`, so the problem gem's own constants are always written
`::Problem::Detailable`. A missing prefix fails with a `NameError` rather than reaching the wrong
constant, because the namespace defines none of the problem gem's names.

The protovalidate integration stays flat (`Protobufable::RequestValidatable`): it is four
constants, and a `Protobufable::Protovalidate` namespace would shadow the protovalidate gem the
same way for little to group.

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

`Problem::RetryInfo` and `BadRequest` look their message classes up in the generated pool rather than
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

connect_rpc_rails' own signatures are ignored in `rbs_collection.yaml`: they stub
`Rails::Railtie.initializer`, as problem's do, and the two library declarations conflict. The
little of it the Connect integration calls is declared in `sig/manual/connect_rpc_rails.rbs`.

`protoc --rbs_out` is not used. It emits `RepeatedField` with two type parameters, which agrees
with neither the collection nor protovalidate, and the Steepfile checks `lib` only, so the spec
fixtures need no signatures.

## Deliberately out of scope

- **RFC 9457 itself.** [problem](https://github.com/sorah/problem) owns it.
- **Connect and gRPC.** [connect_rpc_rails](https://github.com/ivry-inc/connect_rpc_rails) owns
  the protocol. Only the error bridge is here, and it replaces one method of
  `Problem::Rescuable`.
- **OpenAPI generation.** Post-processing a gnostic document is a build step over `.proto`
  sources, not a library that runs in a request.
- **Opaque page tokens.** A protobuf-backed cursor is a small thing to write and a large thing
  to make general.
- **`application/problem+xml`.**
