# frozen_string_literal: true

module YangJSON
  class Transformer
    attr_reader :violations, :selections

    def initialize(schema, mode:, limits:, selections: {})
      raise ArgumentError, "Expected a YangJSON::Schema" unless schema.is_a?(Schema)

      @schema = schema
      @mode = mode
      @limits = limits
      @violations = []
      @selections = selections.dup
    end

    def transform(value)
      object(value, @schema.tree, nil, "", "", metadata_allowed: false)
    end

    private

    def invalid(pointer, message, rule)
      @violations << Violation.new(pointer: pointer.freeze, message: message.freeze, rule: rule.freeze)
    end

    def object(value, nodes, parent, pointer, location, metadata_allowed: true)
      unless value.is_a?(Hash)
        invalid(pointer, "Expected an object", "structure")
        return value
      end
      output = {}
      normalized = {}
      value.each do |name, item|
        next if name.start_with?("@")

        path = Core.pointer(pointer, name)
        unless Core::NAME.match?(name)
          invalid(path, "Invalid YANG member name", "name")
          output[name] = item
          next
        end
        full = if name.include?(":")
                 name
               else
                 (parent ? "#{parent}:#{name}" : name)
               end
        node = nodes[full]
        unless node
          invalid(path, "Unknown schema node", "schema")
          output[full] = item
          normalized[name] = [full, nil]
          next
        end
        expected = @mode == :encode ? full : wire_name(node, parent)
        invalid(path, "Invalid module qualification", "namespace") unless name == expected
        target = @mode == :decode ? full : wire_name(node, parent)
        if output.key?(target)
          invalid(path, "Duplicate normalized member", "duplicate")
          next
        end
        normalized[name] = [target, node]
        output[target] = node_value(item, node, path, Core.pointer(location, full))
      end
      # Resolve data members first: metadata is allowed to precede its target.
      value.each do |name, item| # rubocop:disable Style/CombinableLoops
        next unless name.start_with?("@")

        path = Core.pointer(pointer, name)
        if name == "@"
          invalid(path, "Metadata has no enclosing data node", "metadata") unless metadata_allowed
          output[name] = annotations(item, path, Core.pointer(location, "@"))
          next
        end
        target, node = normalized[name.delete_prefix("@")]
        unless node
          invalid(path, "Metadata must accompany an existing schema node", "metadata")
          output[name] = item
          next
        end
        if node.kind == "leaf-list"
          if !item.is_a?(Array) || !value[name.delete_prefix("@")].is_a?(Array) || item.length > value[name.delete_prefix("@")].length
            invalid(path, "Leaf-list metadata must align with its values", "metadata")
            output["@#{target}"] = item
          else
            output["@#{target}"] = item.each_with_index.map do |entry, index|
              entry.nil? ? nil : annotations(entry, Core.pointer(path, index), Core.pointer(location, "@#{node.name}/#{index}"))
            end
          end
        elsif %w[leaf anyxml].include?(node.kind)
          output["@#{target}"] = annotations(item, path, Core.pointer(location, "@#{node.name}"))
        else
          invalid(path, "Object node metadata belongs inside its @ member", "metadata")
          output["@#{target}"] = item
        end
      end
      output
    end

    def node_value(value, node, pointer, location)
      case node.kind
      when "container" then object(value, node.children, node.module_name, pointer, location)
      when "list"
        unless value.is_a?(Array)
          invalid(pointer, "List must be an array", "structure")
          return value
        end
        entries = value.each_with_index.map do |entry, index|
          object(entry, node.children, node.module_name, Core.pointer(pointer, index), Core.pointer(location, index))
        end
        seen = {}
        entries.each_with_index do |entry, index|
          next unless entry.is_a?(Hash)

          keys = node.keys.map { |name| @mode == :decode ? name : wire_name(node.children.fetch(name), node.module_name) }
          missing = keys.reject { |key| entry.key?(key) }
          missing.each do |key|
            child = node.children.values.find { |candidate| candidate.name == key || wire_name(candidate, node.module_name) == key }
            input_key = @mode == :decode ? wire_name(child, node.module_name) : child.name
            invalid(Core.pointer(Core.pointer(pointer, index), input_key), "Required list key is missing", "key")
          end
          next unless missing.empty? && !keys.empty?

          tuple = keys.map { |key| entry[key] }
          invalid(Core.pointer(pointer, index), "Duplicate list key tuple", "unique") if seen[tuple]
          seen[tuple] = true
        end
        entries
      when "leaf" then typed(value, node.type, node.module_name, pointer, location)
      when "leaf-list"
        unless value.is_a?(Array)
          invalid(pointer, "Leaf-list must be an array", "structure")
          return value
        end
        # jtox omits config; YANG 1.1 permits repeated values for state leaf-lists.
        value.each_with_index.map do |entry, index|
          typed(entry, node.type, node.module_name, Core.pointer(pointer, index), Core.pointer(location, index))
        end

      when "anydata"
        unless value.is_a?(Hash)
          invalid(pointer, "anydata must be an object", "structure")
          return value
        end
        anydata_object(value, pointer, location)
      when "anyxml"
        opaque(value, pointer, anydata: false)
        value
      end
    end

    def typed(value, type, module_name, pointer, location)
      Types.convert(value, type, mode: @mode, module_name: module_name, schema: @schema, limits: @limits,
                                 pointer: location, selections: @selections)
    rescue ConversionError => e
      invalid(pointer, e.message, "type")
      value
    end

    def annotations(value, pointer, location)
      unless value.is_a?(Hash)
        invalid(pointer, "Metadata object must be an object", "metadata")
        return value
      end
      value.to_h do |name, item|
        path = Core.pointer(pointer, name)
        type = @schema.annotations[name]
        if !Core::NAME.match?(name) || !name.include?(":") || !type
          invalid(path, "Unknown or unqualified metadata annotation", "metadata")
          [name, item]
        else
          [name, typed(item, type, name.split(":", 2).first, path, Core.pointer(location, name))]
        end
      end
    end

    def wire_name(node, parent)
      node.module_name == parent ? node.name.split(":", 2).last : node.name
    end

    # Names and values inside schema-less anydata remain in wire form. Only
    # registered annotations can be assigned native types without a content schema.
    def anydata_object(value, pointer, location)
      value.to_h do |name, item|
        path = Core.pointer(pointer, name)
        position = Core.pointer(location, name)
        if name == "@"
          [name, annotations(item, path, position)]
        elsif name.start_with?("@")
          sibling = value[name.delete_prefix("@")]
          invalid(path, "Metadata must accompany a scalar or leaf-list", "metadata") unless value.key?(name.delete_prefix("@")) && !sibling.is_a?(Hash)
          if sibling.is_a?(Array) && sibling != [nil]
            if item.is_a?(Array) && item.length <= sibling.length && sibling.none?(Hash)
              [name, item.each_with_index.map { |entry, i| entry.nil? ? nil : annotations(entry, Core.pointer(path, i), Core.pointer(position, i)) }]
            else
              invalid(path, "Leaf-list metadata must align with its values", "metadata")
              [name, item]
            end
          else
            [name, annotations(item, path, position)]
          end
        else
          invalid(path, "Invalid anydata member name", "anydata") unless Core::NAME.match?(name)
          if item.is_a?(Hash)
            [name, anydata_object(item, path, position)]
          elsif item.is_a?(Array) && item.all?(Hash)
            [name, item.each_with_index.map { |entry, i| anydata_object(entry, Core.pointer(path, i), Core.pointer(position, i)) }]
          else
            opaque(item, path, anydata: true)
            [name, item]
          end
        end
      end
    end

    def opaque(value, pointer, anydata:)
      case value
      when Hash
        value.each do |name, item|
          invalid(Core.pointer(pointer, name), "Invalid anydata member name", "anydata") if anydata && !Core::NAME.match?(name)
          opaque(item, Core.pointer(pointer, name), anydata: anydata)
        end
      when Array
        if anydata
          return if value == [nil]

          objects = value.all?(Hash)
          scalars = value.all? { |entry| entry == [nil] || !(entry.is_a?(Hash) || entry.is_a?(Array) || entry.nil?) }
          unless objects || (scalars && value.uniq.length == value.length)
            invalid(pointer, "anydata array must contain objects or unique scalar values", "anydata")
          end
        end
        value.each_with_index { |item, index| opaque(item, Core.pointer(pointer, index), anydata: anydata) }
      when NilClass
        invalid(pointer, "anydata null is only valid as [null]", "anydata") if anydata
      when Integer
        invalid(pointer, "Opaque JSON integer exceeds the interoperable range", "i-json") if value.abs > ((2**53) - 1)
      when BigDecimal
        invalid(pointer, "Opaque JSON cannot contain native decimal values", "i-json")
      when String
        invalid(pointer, "Opaque JSON requires Unicode strings", "i-json") unless Core.string(value)
      end
    end
  end
end
