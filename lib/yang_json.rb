# frozen_string_literal: true

require_relative "yang_json/version"
require_relative "yang_json/core"
require_relative "yang_json/types"
require_relative "yang_json/schema"
require_relative "yang_json/transformer"

module YangJSON
  # Decode RFC 7951 JSON to module-qualified Ruby values.
  # @param source [String] UTF-8 JSON text
  # @param schema [Schema] immutable caller-defined schema
  # @param strict [Boolean] whether semantic violations raise an exception
  # @return [Document] converted data, diagnostics and union selections
  # @raise [ParseError] malformed JSON or a resource limit violation
  # @raise [ValidationError] a type or structure violation in strict mode
  def self.decode(source, schema, strict: true, **options)
    limits = Core.limits(options)
    value = Core.parse(source, limits)
    transformer = Transformer.new(schema, mode: :decode, limits: limits)
    result = transformer.transform(value)
    raise ValidationError, transformer.violations if strict && !transformer.violations.empty?
    raise ValidationError, transformer.violations unless result.is_a?(Hash)

    Document.new(result, warnings: transformer.violations, union_members: transformer.selections)
  end

  # Encode native values; all validation failures are errors.
  # @param data [Hash] native values with module-qualified modeled keys
  # @param schema [Schema] immutable caller-defined schema
  # @return [String] RFC 7951 JSON
  # @raise [ValidationError] data cannot be represented by the schema
  def self.encode(data, schema, **options)
    limits = Core.limits(options)
    value = Core.copy(data, limits, native: true)
    selections = data.is_a?(Document) ? data.union_members : {}
    transformer = Transformer.new(schema, mode: :encode, limits: limits, selections: selections)
    result = transformer.transform(value)
    raise ValidationError, transformer.violations unless transformer.violations.empty?

    result = Core.copy(result, limits)
    encoded = JSON.generate(Core.precise(result), allow_nan: false, max_nesting: limits[:max_depth])
    raise ConversionError, "Output byte limit exceeded" if encoded.bytesize > limits[:max_bytes]

    encoded
  rescue JSON::GeneratorError
    raise ConversionError, "Invalid JSON output", cause: nil
  end

  # @return [Array<Violation>] all diagnostics, including parse failures
  def self.validate(source, schema, **)
    decode(source, schema, strict: false, **).warnings
  rescue ParseError => e
    [Violation.new(pointer: "", message: e.message, rule: "parse")]
  rescue ValidationError => e
    e.violations
  end

  def self.parse(source, schema:, **)
    decode(source, schema, **)
  end
end
