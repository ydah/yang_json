# Implementation and dependency policy

This project's code is released under MIT. Added runtime and development libraries must offer MIT terms, including their transitive dependencies. Ruby, its default/bundled standard libraries and the system libraries supporting that runtime are the explicit exception. A gem being installed separately does not change its standard-library status. Multiple licenses are acceptable only when MIT is an available alternative, not when a non-MIT license is also required.

The conversion rules in `lib/yang_json/types.rb` and `transformer.rb` implement RFC 7951 sections 4–7 and RFC 7952 section 5. Numeric bounds and decimal precision come from RFC 7950's built-in type definitions. Schema loading validates the documented input data structure; it does not contain a YANG compiler.

During initial development, the pyang jtox plugin source and output were examined to understand its data format, and libyang was executed for comparison. This is not a claim of clean-room development. No translated pyang/libyang implementation has been identified in the Ruby loader or converters. Those tools are no longer installed or executed by this project's development scripts or CI. The orchard schema is declared directly; the compiler-generated fixture has been removed. Accepting a caller's existing jtox data remains supported without invoking pyang.

RFC text and example inputs are fetched only into ignored `tmp/`, with their notices and checksums. They are not part of the MIT source or gem package. Protocol identifiers, type names and limits are represented as data; RFC prose, ABNF and third-party implementation code must not be copied into the library.

Dependency metadata is checked by `script/check_licenses.rb`. Review the actual license and any bundled material when adding or updating a dependency; a metadata check alone does not establish the provenance of every file.
