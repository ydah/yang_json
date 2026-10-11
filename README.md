# yang_json

Read, validate and write [RFC 7951](https://www.rfc-editor.org/rfc/rfc7951) YANG JSON in Ruby, including [RFC 7952](https://www.rfc-editor.org/rfc/rfc7952) metadata. Supply a schema as a Ruby Hash or JSON document. No external schema compiler, YANG parser, or subprocess is required.

## Installation

```ruby
gem "yang_json", "~> 0.1.0"
```

Ruby 3.3 or later, JRuby and TruffleRuby are tested. Runtime dependencies are `json` (2.19.4–3.x), `bigdecimal` and `base64`; no other gem in this family is required. JSON 2.x and 3.x both reject duplicate object members explicitly.

## Schema and data

Define the nodes and their types directly, or load the same structure with `Schema.from_json`. See [schema format](docs/jtox-format.md).

```ruby
require "yang_json"

schema = YangJSON::Schema.new({
  "modules" => { "orchard" => ["o", "urn:example:orchard"] },
  "tree" => { "orchard:grove" => ["container", { "count" => ["leaf", "uint64"] }] },
  "annotations" => {}
})
data = YangJSON.decode('{"orchard:grove":{"count":"123"}}', schema)
data["orchard:grove"]["orchard:count"] # => 123
YangJSON.encode(data, schema)           # => '{"orchard:grove":{"count":"123"}}'
schema.lookup("/orchard:grove/count").type # => "uint64"
YangJSON.validate('{"orchard:grove":{"count":123}}', schema).first.pointer
# => "/orchard:grove/count"
```

`decode` returns a mutable `YangJSON::Document`, a Hash with `warnings` and `union_members`. All modeled Ruby keys are **module-qualified**, including descendants. `encode` requires that form and writes the minimally qualified names required by RFC 7951. Opaque `anydata`/`anyxml` content retains its wire names. The schema and its nodes are immutable and shareable; conversions do not mutate inputs. `YangJson` is an alias for `YangJSON`.

`YangJSON.parse(json, schema: schema)` is an alternate spelling of `decode`. `schema.lookup` accepts a slash-separated path or an array of names; descendants may use simple or qualified names. List nodes expose their qualified `keys`.

## Values

| YANG type | Ruby value | JSON representation |
|---|---|---|
| int8/int16/int32, uint8/uint16/uint32 | Integer, within the type's range | Number |
| int64, uint64 | Integer, within the type's range | Decimal string |
| decimal64 | BigDecimal, exact scaled 64-bit value | Decimal string |
| string, enumeration | Unicode String | String |
| boolean | true / false | true / false |
| bits | Array of unique names | Whitespace-separated string |
| binary | ASCII-8BIT String (`bytes.b`) | Standard padded base64 |
| identityref | Module-qualified String | Local name or qualified name |
| empty | true | `[null]` |
| union | Native value of a matching member | Matching member's JSON type |
| instance-identifier | String | Absolute path with module-name qualification |
| leafref | Native value of the resolved target type | Target type's representation |
| anydata | Hash of opaque JSON values | Object subject to RFC 7951 §5.5 |
| anyxml | Opaque JSON value | I-JSON value |

Decimal strings normalize on encoding (`"12.30"` becomes `"12.3"`, negative zero becomes `"0.0"`). Integer signs/leading zeros, bit whitespace and local identity prefixes also normalize. Binary decoding requires canonical padding and zero pad bits. Integer JSON tokens containing fractions/exponents are not accepted as small integer values.

Unions try compatible members in schema order, using the JSON type during decoding. Documents remember the selected member at each path, so JSON `1` and `"1"` remain distinct even when both become Ruby Integers. Plain Hash inputs use the first compatible member. Moving values to different paths, reordering arrays, or discarding the Document can discard this original selection; select unambiguous schema members when that distinction matters.

Metadata uses `@` inside container/list-entry/anydata objects, or `@module:leaf` beside modeled native leaves, anyxml and leaf-lists. Annotation names always stay qualified, and values use their declared types. Leaf-list metadata arrays preserve null holes and may omit trailing nulls. Registered annotations within opaque anydata are converted; its data values otherwise remain in wire form.

## Validation and limits

```ruby
data = YangJSON.decode(json, schema, strict: false)
data.warnings.each { |violation| warn "#{violation.pointer}: #{violation.message}" }
```

Strict decoding raises `ValidationError`; lenient decoding retains unknown or invalid values and attaches diagnostics. It does not make invalid configuration safe. Encoding is always strict. Unknown schema fields cannot be serialized until the schema is extended or the fields are removed. Modeled keys normalize in lenient results, so malformed namespace aliases cannot always be preserved independently.

`ValidationError#violations` contains `Violation` objects with `pointer`, `message` and `rule`; `ValidationError#pointer` identifies the first failure. Pointers address the input document. `validate` returns violations, including parse failures. `ParseError` covers malformed JSON/schemas and resource limits; `ConversionError` covers generation errors. All inherit from `YangJSON::Error`. Unknown options, nonpositive limits and invalid schema arguments raise `ArgumentError`.

| Option | Default | Applies to |
|---|---:|---|
| `max_bytes` | 16 MiB | Input/output JSON; aggregate native string/key bytes |
| `max_depth` | 32 | JSON/native/schema nesting |
| `max_nodes` | 100,000 | Total values visited |
| `max_items` | 10,000 | Members of an object or items of an array |
| `max_binary_bytes` | 1 MiB | Decoded/encoded binary payload |

Pass overrides to `decode`, `encode`, `parse`, `validate` or `Schema.from_json`. Integer/decimal strings have an additional 128-character bound. Invalid Unicode, noncharacters, nonfinite numbers and duplicate members always fail, including lenient mode. Opaque integer values are restricted to ±(2^53−1); represent larger numbers as strings. Large objects, cyclic Ruby data and deep nesting are rejected before recursive conversion can exhaust normal limits.

## Scope

| Supported | Outside the 0.1 scope |
|---|---|
| RFC 7951 names, all built-in value encodings, containers/lists, key presence and duplicate key tuples | Parsing YANG/YIN; XML, NETCONF and RESTCONF transport APIs |
| Pre-resolved built-in types, leafrefs, union members, and augmented nodes supplied by the caller | Compiling YANG typedefs, uses, augment, choice, RPC, action or notification definitions |
| Exact decimal64, 64-bit integers, union member selection and identity namespace rules | Complete YANG semantic/datastore validation |
| RFC 7952 typed annotations on each node category | Interpreting annotation application semantics |
| Structural schema-less anydata validation and opaque anyxml | Inferring or resolving schemas inside opaque content |

**The schema format omits semantic constraints.** This gem cannot validate enumeration membership, identity derivation, allowed bit names/positions, derived range/length/pattern restrictions, mandatory/default/config properties, choice exclusivity, min/max-elements, unique statements, must/when expressions, leafref existence or instance-identifier existence. It does not add defaults or reorder system-ordered collections. Repeated leaf-list values are accepted because state leaf-lists may contain duplicates and the schema omits `config`. Instance-identifier syntax and namespace changes are checked, but node existence and predicate suitability are not resolved. See [schema format notes](docs/jtox-format.md).

## Development and conformance

```sh
bundle install
bundle exec rake test
COVERAGE=1 bundle exec rake test
bundle exec rbs -r bigdecimal -I sig validate
```

The Ruby suite covers all 20 JSON/path examples in RFC 7951/7952, including the deliberately invalid union value and complete Appendix A. Test schemas are declared locally. RFC excerpts are fetched with pinned SHA-256 hashes into ignored `tmp/rfc/`, retaining source notices and extraction corrections. These documents and examples are test inputs, never dependencies or packaged files. No external implementation is downloaded or executed by the tests. See [conformance notes](docs/conformance.md).

`bundle exec ruby script/benchmark.rb` measures a bounded large record and limit rejection. CI tests maintained CRuby versions, head, JRuby and TruffleRuby on Linux/macOS, and both JSON major versions. Coverage must reach 90%.

## License and security

Released under the [MIT License](LICENSE.txt). Added runtime and development dependencies must offer MIT terms; Ruby, its standard libraries and their system dependencies are the explicit exception. See [implementation and dependency policy](docs/implementation.md). Report vulnerabilities through the private channel in [SECURITY.md](SECURITY.md).
