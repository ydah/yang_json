# frozen_string_literal: true

if ENV["COVERAGE"] == "1"
  require "simplecov"
  SimpleCov.start do
    add_filter "/spec/"
    add_filter "/script/"
    enable_coverage :branch
    minimum_coverage line: 90
    track_files "lib/**/*.rb"
  end
end
require "yang_json"

module Fixtures
  def schema
    @schema ||= YangJSON::Schema.from_jtox(File.read(File.join(__dir__, "fixtures/orchard.json")))
  end

  def typed_schema(type, kind: "leaf")
    YangJSON::Schema.new({ "modules" => { "orchard" => ["o", "urn:example:orchard"], "other" => ["x", "urn:example:other"] },
                           "tree" => { "orchard:value" => [kind, type] }, "annotations" => {} })
  end

  def decode_value(value, type, **)
    YangJSON.decode(JSON.generate("orchard:value" => value), typed_schema(type), **).fetch("orchard:value")
  end

  def encode_value(value, type, **)
    JSON.parse(YangJSON.encode({ "orchard:value" => value }, typed_schema(type), **)).fetch("orchard:value")
  end

  def grove(values = nil, **options)
    values = options.select { |key, _| key.is_a?(String) } if values.nil?
    options = options.reject { |key, _| key.is_a?(String) }
    YangJSON.decode(JSON.generate("orchard:grove" => values), schema, **options)
  end
end
RSpec.configure { |config| config.include Fixtures }
