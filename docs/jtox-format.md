# Schema input format

Construct a schema with `YangJSON::Schema.new(hash)` or `YangJSON::Schema.from_json(text)`. The format remains compatible with pre-existing jtox inputs; `from_jtox` is an alias for `from_json`. The gem does not run or install pyang. The checked-in orchard schema is maintained directly as test data.

A schema has `modules`, `tree` and `annotations` objects. `modules` maps module names to `[XML prefix, namespace URI]`. Imported modules can appear without data nodes. The JSON encoding uses the module name, never its XML prefix.

Tree entries use qualified names at the top level and across augment module boundaries, with simple names for same-module descendants. The loader indexes every node by its fully qualified name. Definitions are:

| Node | Definition |
|---|---|
| container | `["container", children]` |
| list | `["list", children, [[key_module, key_name], ...]]` |
| leaf / leaf-list | `[kind, type]` |
| anydata / anyxml | `[kind]` |

A type is a primitive name, `["decimal64", fraction_digits]` or `["union", member_types]`. Typedefs resolve to built-in types; leafrefs resolve to the referred leaf's type. Nested unions remain recursive. Annotation entries map a qualified annotation name directly to a type. Fraction digits must be 1–18. Unknown node kinds, unresolved types and malformed schemas are rejected.

Supply expanded `uses` nodes and module-qualified augmented children. The format has no `choice`/`case` constraints. Lists declare their keys; state lists may have no keys. RPC, action and notification schema nodes are unsupported.

This format does not represent enumeration values, identity bases, bit positions/names, derived ranges, string patterns/lengths, defaults, mandatory/config, min/max-elements, unique, ordering, must/when or reference-existence constraints. Loading this schema is therefore insufficient for full YANG validation. Applications that need these checks must validate the omitted constraints separately.
