# Conformance checks

The Ruby suite tests all 20 JSON/path examples from RFC 7951 and RFC 7952, including the invalid union example, all metadata placements and the complete Appendix A. Sources and extracted examples are checksum-pinned in `script/rfc_sources.json` and stored only in ignored `tmp/rfc/`, with originals, notices and correction notes. Schemas used by these tests are declared directly as Ruby values. The orchard JSON schema is also maintained directly, without a schema compiler.

The extractor removes page headers and indentation, wraps member fragments, and removes omission markers from the metadata examples. Changes are recorded in the extraction manifest. RFC prose, ABNF, external YANG modules and third-party tool implementations are neither checked in nor packaged.

Verified RFC 7951 erratum 7020 applies module-context rules to identityref leaf-lists. The tests cover both leaves and leaf-lists. RFC 7950 supplies numeric bounds and decimal precision rules; the tests also check namespaces, duplicate keys, binary padding, invalid Unicode and configured resource limits.

The compact schema format describes structure and value encodings, not full YANG datastore semantics. Enumeration membership, identity ancestry, allowed bit names, derived restrictions, choice exclusivity and reference existence remain outside this converter's scope. See the [schema format](jtox-format.md).

The previous pyang/libyang comparison runner has been removed under the MIT-only dependency policy. Conformance claims now refer to the RFC-based Ruby tests, not to agreement with an external implementation. See the [implementation policy](implementation.md) for the development history and limits of the provenance review.
