# frozen_string_literal: true

require "json"
require "base64"
require "bigdecimal"

module YangJSON
  class Error < StandardError; end
  class ParseError < Error; end
  Violation = Data.define(:pointer, :message, :rule)

  class ValidationError < Error
    attr_reader :violations, :pointer

    def initialize(violations)
      @violations = violations.freeze
      @pointer = violations.first&.pointer || ""
      super(violations.first&.message || "Invalid YANG data")
    end
  end

  class ConversionError < Error; end

  class Document < Hash
    attr_reader :warnings, :union_members

    def initialize(values, warnings:, union_members: {})
      super()
      update(values)
      @warnings = warnings.freeze
      @union_members = union_members.freeze
    end
  end

  module Core
    IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_.-]*\z/
    NAME = /\A(?:[A-Za-z_][A-Za-z0-9_.-]*:)?[A-Za-z_][A-Za-z0-9_.-]*\z/
    DEFAULTS = { max_bytes: 16 * 1024 * 1024, max_depth: 32, max_nodes: 100_000, max_items: 10_000, max_binary_bytes: 1024 * 1024 }.freeze

    module_function

    def limits(options)
      unknown = options.keys - DEFAULTS.keys
      raise ArgumentError, "Unknown limit option" unless unknown.empty?

      result = DEFAULTS.merge(options)
      raise ArgumentError, "Limits must be positive integers" unless result.values.all? { |value| value.is_a?(Integer) && value.positive? }

      result.freeze
    end

    def pointer(parent, name)
      "#{parent}/#{name.to_s.gsub("~", "~0").gsub("/", "~1")}"
    end

    def parse(source, limits)
      raise ParseError, "JSON source must be a string" unless source.is_a?(String)
      raise ParseError, "Input byte limit exceeded" if source.bytesize > limits[:max_bytes]

      source = source.dup.force_encoding(Encoding::UTF_8)
      raise ParseError, "Invalid UTF-8" unless source.valid_encoding?

      result = JSON.parse(source, allow_duplicate_key: false, max_nesting: limits[:max_depth], allow_nan: false)
      copy(result, limits)
    rescue JSON::ParserError, EncodingError, ArgumentError
      raise ParseError, "Invalid JSON", cause: nil
    end

    def string(value)
      return false unless value.is_a?(String) && value.valid_encoding? && (value.encoding == Encoding::UTF_8 || value.ascii_only?)

      value.each_codepoint.none? { |point| (0xFDD0..0xFDEF).cover?(point) || (point & 0xFFFF) >= 0xFFFE }
    end

    def copy(value, limits = DEFAULTS, native: false, depth: 0, budget: [0, 0])
      budget[0] += 1
      raise ParseError, "Node count limit exceeded" if budget[0] > limits[:max_nodes]
      raise ParseError, "Nesting limit exceeded" if depth > limits[:max_depth]

      case value
      when Hash
        raise ParseError, "Object member limit exceeded" if value.length > limits[:max_items]
        raise ParseError, "Invalid JSON member name" unless value.keys.all? { |name| string(name) }

        budget[1] += value.keys.sum(&:bytesize)
        raise ParseError, "Aggregate string byte limit exceeded" if budget[1] > limits[:max_bytes]

        value.to_h { |name, item| [name.dup, copy(item, limits, native: native, depth: depth + 1, budget: budget)] }
      when Array
        raise ParseError, "Array item limit exceeded" if value.length > limits[:max_items]

        value.map { |item| copy(item, limits, native: native, depth: depth + 1, budget: budget) }
      when String
        raise ParseError, "Invalid Unicode string" unless (native && value.encoding == Encoding::ASCII_8BIT) || string(value)

        budget[1] += value.bytesize
        raise ParseError, "String byte limit exceeded" if budget[1] > limits[:max_bytes]

        value.dup
      when Float
        raise ParseError, "Non-finite number" unless value.finite?

        value
      when BigDecimal
        raise ParseError, "Unexpected decimal object" unless native && value.finite?

        value
      when Integer, TrueClass, FalseClass, NilClass then value
      else raise ParseError, "Unsupported Ruby value"
      end
    end

    def freeze_tree(value)
      case value
      when Hash then value.each do |key, item|
        key.freeze
        freeze_tree(item)
      end
      when Array then value.each { |item| freeze_tree(item) }
      end
      value.freeze
    end

    def precise(value)
      case value
      when Hash then value.transform_values { |item| precise(item) }
      when Array then value.map { |item| precise(item) }
      when Float
        return value unless RUBY_ENGINE == "truffleruby"

        number = format("%.17g", value)
        number += ".0" unless number.match?(/[.eE]/)
        JSON::Fragment.new(number)
      else value
      end
    end
  end
end
