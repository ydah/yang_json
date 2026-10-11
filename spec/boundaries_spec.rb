# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Input limits and schema validation" do
  it "rejects duplicate members with every JSON parser version" do
    ['{"orchard:grove":{},"orchard:grove":{}}', '{"orchard:grove":{"label":"x","label":"y"}}'].each do |source|
      expect { YangJSON.decode(source, schema) }.to raise_error(YangJSON::ParseError)
    end
  end

  it "rejects invalid Unicode and nonfinite numbers" do
    ["\xff".b, '{"orchard:grove":{"label":"\ud800"}}', '{"orchard:grove":{"label":"\uffff"}}',
     '{"orchard:grove":{"label":"\ufdd0"}}', '{"orchard:grove":{"xml":1e400}}'].each do |source|
      expect { YangJSON.decode(source, schema) }.to raise_error(YangJSON::ParseError)
    end
    [Float::INFINITY, BigDecimal("NaN"), Object.new, "\xff".dup.force_encoding("UTF-8")].each do |value|
      expect { YangJSON.encode({ "orchard:grove" => { "orchard:xml" => value } }, schema) }.to raise_error(YangJSON::ParseError)
    end
    expect { YangJSON.encode({ "\uffff" => 1 }, schema) }.to raise_error(YangJSON::ParseError)
  end

  it "enforces byte, tree, array and member budgets for both directions" do
    expect { YangJSON.decode(1, schema) }.to raise_error(YangJSON::ParseError)
    expect { YangJSON.decode("{} ", schema, max_bytes: 2) }.to raise_error(YangJSON::ParseError)
    expect { grove({ "tags" => %w[a b] }, max_items: 1) }.to raise_error(YangJSON::ParseError)
    expect { grove({ "label" => "a", "small" => 1 }, max_items: 1) }.to raise_error(YangJSON::ParseError)
    expect { grove({ "label" => "a" }, max_nodes: 2) }.to raise_error(YangJSON::ParseError)
    expect { grove({ "xml" => [[[1]]] }, max_depth: 3) }.to raise_error(YangJSON::ParseError)
    expect { YangJSON.encode({ "orchard:grove" => { "orchard:label" => "too long" } }, schema, max_bytes: 3) }.to raise_error(YangJSON::ParseError)
    expect { YangJSON.encode({}, schema, max_bytes: 1) }.to raise_error(YangJSON::ConversionError)
    expect { YangJSON.encode({ "orchard:grove" => { "orchard:tags" => ["a" * 100, "a" * 100] } }, schema, max_bytes: 180) }.to raise_error(YangJSON::ParseError)
    nested = []
    nested << nested
    expect { YangJSON.encode({ "orchard:grove" => { "orchard:xml" => nested } }, schema) }.to raise_error(YangJSON::ParseError)
    expect { YangJSON.decode("{}", schema, max_depth: 0) }.to raise_error(ArgumentError)
    expect { YangJSON.decode("{}", schema, unknown: 2) }.to raise_error(ArgumentError)
    expect { YangJSON.decode("{}", nil) }.to raise_error(ArgumentError)
  end

  it "loads immutable schemas and looks up qualified or relative descendants" do
    expect(schema.lookup("/orchard:grove/count").type).to eq("uint64")
    expect(schema.lookup(%w[orchard:grove orchard-extra:altitude]).type).to eq("int32")
    expect(schema.lookup("/orchard:grove/basket").keys).to eq(["orchard:name"])
    expect(schema.lookup("/missing")).to be_nil
    expect(schema.lookup(nil)).to be_nil
    expect(schema.tree).to be_frozen
    expect(schema.modules.values.first).to be_frozen
    expect(schema.annotations).to be_frozen
  end

  [{}, nil, [], { "modules" => {}, "tree" => [] }].each do |data|
    it("rejects missing schema objects #{data.inspect}") { expect { YangJSON::Schema.from_jtox(JSON.generate(data)) }.to raise_error(YangJSON::ParseError) }
  end

  [
    ["leaf"], %w[leaf leafref], %w[leaf decimal64], ["leaf", ["decimal64", 0]], ["leaf", ["decimal64", 19]],
    ["leaf", ["union", []]], ["leaf", ["union", ["unknown"]]], ["leaf", 1], ["leaf", ["oops", 1]],
    ["container"], ["container", []], ["list", {}, ["key"]], ["list", {}, [%w[orchard missing]]],
    %w[anyxml bad], ["action"], nil
  ].each_with_index do |definition, index|
    it "rejects malformed jtox node #{index}" do
      source = { "modules" => { "orchard" => ["o", "urn:orchard"] }, "tree" => { "orchard:x" => definition }, "annotations" => {} }
      expect { YangJSON::Schema.new(source) }.to raise_error(YangJSON::ParseError)
    end
  end

  it "rejects ambiguous module names, schema aliases and invalid annotations" do
    source = JSON.parse(File.read(File.join(__dir__, "fixtures/orchard.json")))
    source["modules"]["bad:name"] = %w[p uri]
    expect { YangJSON::Schema.new(source) }.to raise_error(YangJSON::ParseError)
    source["modules"].delete("bad:name")
    source["tree"]["orchard:grove"][1]["orchard:count"] = %w[leaf string]
    expect { YangJSON::Schema.new(source) }.to raise_error(YangJSON::ParseError)
    source["tree"] = { "unqualified" => %w[leaf string] }
    expect { YangJSON::Schema.new(source) }.to raise_error(YangJSON::ParseError)
    source["tree"] = { "bad/name" => %w[leaf string] }
    expect { YangJSON::Schema.new(source) }.to raise_error(YangJSON::ParseError)
    source["tree"] = {}
    source["annotations"]["source"] = "string"
    expect { YangJSON::Schema.new(source) }.to raise_error(YangJSON::ParseError)
  end
end
