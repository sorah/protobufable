# Errors

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

A controller renders them as `application/problem+json` once it includes `Problem::Rescuable`,
from problem. An error escaping before dispatch needs problem's `Problem::ExceptionsApp`
instead; see its README.

```ruby
class ApplicationController < ActionController::API
  include Problem::Rescuable
end
```

A value the enum does not define, or one carrying no annotation, raises when the class is
defined, so a typo fails on boot rather than on the first request that reaches the error.

The status is a property of the problem type, not of the code path that raised it. Several
values may publish one identifier where telling them apart would leak something; because
`Problem::I18nable` keys titles by the identifier, such values share a title too, so the
distinction cannot come back through the title instead.

To answer these errors over Connect RPC, see [Connect RPC](connect.md).

## An enum annotated one option per property

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

## Publishing the enum value

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

## Machine-readable detail

RFC 9457 reserves `detail` for prose. Anything a client acts on goes in `information`, as packed
`google.protobuf.Any`:

```ruby
class InvalidRequest < Errors::ApiError
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

To answer a broken `buf.validate` rule with it, see
[Answering a broken rule](validation.md#answering-a-broken-rule).

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
