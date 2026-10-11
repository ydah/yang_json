# Security

Report vulnerabilities privately through [GitHub security advisories](https://github.com/ydah/yang_json/security/advisories/new).
Include the Ruby/json versions, a minimal schema and input, and the observed impact. Do not include credentials or private configuration data.

The 0.1.x series receives security fixes. This gem converts RFC 7951 data using a caller-supplied schema; it does not authenticate input, execute XPath, resolve remote modules, or implement complete YANG datastore validation. Use a full YANG validator when semantic constraints are required.

JSON member duplication, invalid UTF-8/noncharacters, nonfinite numbers, malformed metadata, and structure/type violations are rejected. Encoding always validates. Lenient decoding preserves unsupported values with warnings and must not be treated as accepted configuration. Review `warnings` before using such data.

Byte, nesting, node, collection and binary limits apply before or during conversion. Schema loading is also bounded. Raising these limits increases resource exposure. Pass trusted schemas and limits; protect application-level request sizes and concurrency separately. `anyxml` and schema-less `anydata` are opaque data, never executable XML or code.

Conformance documents and their notices are downloaded into ignored `tmp/` only. External implementations are not downloaded or executed by the tests. They are excluded from Git and the gem package. Dependencies retain their own licenses.
