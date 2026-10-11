# frozen_string_literal: true

module YangJSON
  class Node
    attr_reader :name, :module_name, :kind, :type, :children, :keys

    def initialize(name:, kind:, type: nil, children: {}, keys: [])
      @name = name.freeze
      @module_name = name.split(":", 2).first.freeze
      @kind = kind.freeze
      @type = Core.freeze_tree(type)
      @children = children.freeze
      @keys = Core.freeze_tree(keys)
      freeze
    end
  end

  class Schema
    attr_reader :modules, :tree, :annotations

    # @param source [String] a schema in the documented JSON format
    # @return [Schema] immutable schema
    def self.from_json(source, **options)
      limits = Core.limits(options)
      new(Core.parse(source, limits), limits: limits)
    end

    class << self
      alias from_jtox from_json
    end

    def initialize(data, limits: Core::DEFAULTS)
      raise ParseError, "jtox schema must contain modules, tree, and annotations" unless data.is_a?(Hash) && %w[modules tree annotations].all? do |key|
        data[key].is_a?(Hash)
      end

      data = Core.copy(data, limits)
      @modules = data.fetch("modules")
      @modules.each do |name, definition|
        unless Core::IDENTIFIER.match?(name) && definition.is_a?(Array) && definition.length == 2 && definition.all?(String) && Core::IDENTIFIER.match?(definition[0])
          raise ParseError, "Invalid jtox module definition"
        end
      end
      @modules = Core.freeze_tree(@modules)
      @tree = build_nodes(data.fetch("tree"), nil)
      @annotations = data.fetch("annotations").to_h do |name, type|
        qualified(name, nil)
        check_type(type)
        [name, Core.freeze_tree(type)]
      end.freeze
      freeze
    end

    # @param path [String, Array<String>] qualified root and simple/qualified descendants
    # @return [Node, nil] schema node, or nil when absent
    def lookup(path)
      parts = path.is_a?(String) ? path.delete_prefix("/").split("/") : path
      return nil unless parts.is_a?(Array)

      nodes = tree
      parent = nil
      node = nil
      parts.each do |part|
        name = part.include?(":") ? part : "#{parent}:#{part}"
        node = nodes[name]
        return nil unless node

        parent = node.module_name
        nodes = node.children
      end
      node
    end

    private

    def qualified(name, parent)
      raise ParseError, "Invalid jtox node name" unless name.is_a?(String) && Core::NAME.match?(name)

      full = name.include?(":") ? name : "#{parent}:#{name}"
      raise ParseError, "Unknown or absent jtox module" unless modules.key?(full.split(":", 2).first)

      full
    end

    def check_type(type)
      if type.is_a?(String)
        raise ParseError, "Unsupported or unresolved jtox type" unless Types::PRIMITIVES.include?(type)
      elsif type.is_a?(Array) && type.length == 2
        if type[0] == "decimal64"
          raise ParseError, "Invalid fraction-digits" unless type[1].is_a?(Integer) && (1..18).cover?(type[1])
        elsif type[0] == "union" && type[1].is_a?(Array) && !type[1].empty?
          type[1].each { |member| check_type(member) }
        else
          raise ParseError, "Invalid jtox compound type"
        end
      else
        raise ParseError, "Invalid jtox type"
      end
    end

    def build_nodes(tree, parent)
      raise ParseError, "Invalid jtox tree" unless tree.is_a?(Hash)

      tree.each_with_object({}) do |(name, definition), output|
        full = qualified(name, parent)
        raise ParseError, "Duplicate normalized jtox node" if output.key?(full)
        raise ParseError, "Invalid jtox node" unless definition.is_a?(Array)

        kind = definition[0]
        case kind
        when "container", "list"
          expected = kind == "list" ? 3 : 2
          raise ParseError, "Invalid jtox branch" unless definition.length == expected

          children = build_nodes(definition[1], full.split(":", 2).first)
          keys = kind == "list" ? definition[2] : []
          raise ParseError, "Invalid jtox list keys" unless keys.is_a?(Array) && keys.all? { |key| key.is_a?(Array) && key.length == 2 && key.all?(String) }

          keys = keys.map { |key| key.join(":") }
          raise ParseError, "List key must reference a child leaf" unless keys.uniq == keys && keys.all? { |key| children[key]&.kind == "leaf" }

          output[full] = Node.new(name: full, kind: kind, children: children, keys: keys)
        when "leaf", "leaf-list"
          raise ParseError, "Invalid jtox leaf" unless definition.length == 2

          check_type(definition[1])
          output[full] = Node.new(name: full, kind: kind, type: definition[1])
        when "anydata", "anyxml"
          raise ParseError, "Invalid jtox opaque node" unless definition.length == 1

          output[full] = Node.new(name: full, kind: kind)
        else raise ParseError, "Unsupported jtox node kind"
        end
      end.freeze
    end
  end
end
