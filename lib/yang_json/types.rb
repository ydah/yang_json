# frozen_string_literal: true

module YangJSON
  module Types
    PRIMITIVES = %w[int8 int16 int32 int64 uint8 uint16 uint32 uint64 string enumeration boolean bits binary identityref empty
                    instance-identifier].each(&:freeze).freeze
    INTEGER_TYPES = %w[int8 int16 int32 int64 uint8 uint16 uint32 uint64].each(&:freeze).freeze

    module_function

    def convert(value, type, mode:, module_name:, schema:, limits:, pointer:, selections:)
      name, parameter = type.is_a?(Array) ? type : [type, nil]
      if name == "union"
        indices = (0...parameter.length).to_a
        preferred = selections[pointer] if mode == :encode
        indices = [preferred] + (indices - [preferred]) if preferred && indices.include?(preferred)
        indices.each do |index|
          result = convert(value, parameter[index], mode: mode, module_name: module_name, schema: schema, limits: limits,
                                                    pointer: "#{pointer}/union#{index}", selections: selections)
          selections[pointer] = index if mode == :decode
          return result
        rescue ConversionError
          next
        end
        raise ConversionError, "Value does not match any union member"
      end
      case name
      when *INTEGER_TYPES then integer(value, name, mode)
      when "decimal64" then decimal(value, parameter, mode)
      when "string", "enumeration"
        raise ConversionError, "Expected a Unicode string" unless Core.string(value)

        value.dup
      when "boolean"
        raise ConversionError, "Expected a boolean" unless [true, false].include?(value)

        value
      when "empty"
        expected = mode == :decode ? [nil] : true
        raise ConversionError, "Invalid empty value" unless value == expected

        mode == :decode ? true : [nil]
      when "bits" then bits(value, mode)
      when "binary" then binary(value, mode, limits[:max_binary_bytes])
      when "identityref" then identity(value, mode, module_name, schema)
      when "instance-identifier"
        instance_identifier(value, schema)
        value.dup
      else raise ConversionError, "Unsupported data type"
      end
    end

    def integer(value, type, mode)
      bits = type.delete_prefix("u").delete_prefix("int").to_i
      if mode == :decode && bits == 64
        raise ConversionError, "64-bit integer must be a decimal string" unless value.is_a?(String) && value.match?(/\A[+-]?[0-9]+\z/)
        raise ConversionError, "Integer representation is too long" if value.length > 128

        number = Integer(value, 10)
      else
        raise ConversionError, "Expected an integer" unless value.is_a?(Integer)

        number = value
      end
      range = type.start_with?("u") ? (0..((2**bits) - 1)) : (-(2**(bits - 1))..((2**(bits - 1)) - 1))
      raise ConversionError, "Integer is out of range" unless range.cover?(number)

      mode == :encode && bits == 64 ? number.to_s : number
    end

    def decimal(value, digits, mode)
      if mode == :decode
        unless value.is_a?(String) && value.length <= 128 && value.match?(/\A[+-]?[0-9]+(?:\.[0-9]+)?\z/)
          raise ConversionError, "decimal64 must be a decimal string"
        end

        number = BigDecimal(value)
      else
        raise ConversionError, "decimal64 requires BigDecimal" unless value.is_a?(BigDecimal) && value.finite?

        number = value
      end
      scaled = number * (10**digits)
      raise ConversionError, "decimal64 precision or range exceeded" unless scaled.frac.zero? && scaled >= -(2**63) && scaled <= (2**63) - 1

      if mode == :decode
        number
      else
        (number.zero? ? "0.0" : number.to_s("F"))
      end
    end

    def bits(value, mode)
      if mode == :decode
        raise ConversionError, "bits requires a string" unless value.is_a?(String)

        names = value.split(/[ \t\r\n]+/).reject(&:empty?)
      else
        raise ConversionError, "bits requires an array" unless value.is_a?(Array)

        names = value
      end
      unless names.all? { |name| name.is_a?(String) && Core::IDENTIFIER.match?(name) } && names.uniq == names
        raise ConversionError, "Invalid or duplicate bit name"
      end

      mode == :decode ? names : names.join(" ")
    end

    def binary(value, mode, limit)
      raise ConversionError, "binary requires a string" unless value.is_a?(String)

      if mode == :decode
        raise ConversionError, "Decoded binary limit exceeded" if value.bytesize > ((limit + 2) / 3) * 4

        bytes = Base64.strict_decode64(value)
        raise ConversionError, "Noncanonical base64 value" unless Base64.strict_encode64(bytes) == value
      else
        raise ConversionError, "binary requires an ASCII-8BIT string" unless value.encoding == Encoding::ASCII_8BIT

        bytes = value
      end
      raise ConversionError, "Binary byte limit exceeded" if bytes.bytesize > limit

      mode == :decode ? bytes : Base64.strict_encode64(bytes)
    rescue ArgumentError
      raise ConversionError, "Invalid base64 value", cause: nil
    end

    def identity(value, mode, parent, schema)
      raise ConversionError, "Invalid identity name" unless value.is_a?(String) && Core::NAME.match?(value)
      raise ConversionError, "Ruby identity must be module-qualified" if mode == :encode && !value.include?(":")

      full = value.include?(":") ? value : "#{parent}:#{value}"
      module_name, name = full.split(":", 2)
      raise ConversionError, "Unknown identity module" unless schema.modules.key?(module_name)

      if mode == :decode
        full
      else
        (module_name == parent ? name : full)
      end
    end

    def instance_identifier(value, schema)
      raise ConversionError, "instance-identifier must be an absolute path" unless Core.string(value) && value.start_with?("/")

      offset = 0
      parent = nil
      while offset < value.length
        match = %r{\G/((?:[A-Za-z_][A-Za-z0-9_.-]*:)?[A-Za-z_][A-Za-z0-9_.-]*)}.match(value, offset)
        raise ConversionError, "Invalid instance-identifier step" unless match

        name = match[1]
        module_name = name.include?(":") ? name.split(":", 2).first : parent
        unless module_name && schema.modules.key?(module_name) && (name.include?(":") == (module_name != parent))
          raise ConversionError, "Invalid instance-identifier namespace"
        end

        parent = module_name
        offset = match.end(0)
        predicate_kind = nil
        while value[offset] == "["
          predicate = /\G\[[ \t]*(?:(?:((?:[A-Za-z_][A-Za-z0-9_.-]*:)?[A-Za-z_][A-Za-z0-9_.-]*|\.)[ \t]*=[ \t]*(?:'[^']*'|"[^"]*"))|[1-9][0-9]*)[ \t]*\]/.match(
            value, offset
          )
          raise ConversionError, "Invalid instance-identifier predicate" unless predicate

          key = predicate[1]
          kind = key && key != "." ? :key : :single
          raise ConversionError, "Incompatible instance-identifier predicates" if predicate_kind && (predicate_kind != :key || kind != :key)

          predicate_kind = kind
          if key && key != "." && key.include?(":")
            module_name = key.split(":", 2).first
            raise ConversionError, "Invalid predicate namespace" if module_name == parent || !schema.modules.key?(module_name)
          end
          offset = predicate.end(0)
        end
      end
    end
  end
end
