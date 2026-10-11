# frozen_string_literal: true

require "spec_helper"

RSpec.describe YangJSON do
  it "converts all names, typedefs, leafrefs, augmented fields, and native values" do
    data = grove("label" => "orchard", "enabled" => true, "count" => "18446744073709551615", "reference" => "2",
                 "price" => "12.30", "mask" => "ripe local", "blob" => "AP8=", "present" => [nil], "variety" => "apple",
                 "varieties" => ["apple", "orchard:fruit"], "orchard-extra:altitude" => 25)
    values = data.fetch("orchard:grove")
    expect(values.keys).to all(include(":"))
    expect(values).to include("orchard:count" => (2**64) - 1, "orchard:reference" => 2, "orchard:price" => BigDecimal("12.30"),
                              "orchard:mask" => %w[ripe local], "orchard:blob" => "\x00\xff".b, "orchard:present" => true,
                              "orchard:varieties" => %w[orchard:apple orchard:fruit])
    expect(YangJSON.decode(YangJSON.encode(data, schema), schema)).to eq(data)
    expect(data.warnings).to be_empty
  end

  it "strictly enforces module qualification and reports original wire pointers" do
    ["orchard:label", "altitude"].each do |name|
      expect { grove(name => "bad") }.to raise_error(YangJSON::ValidationError)
    end
    expect { YangJSON.decode('{"grove":{}}', schema) }.to raise_error(YangJSON::ValidationError)
    expect { YangJSON.encode({ "orchard:grove" => { "count" => 1 } }, schema) }.to raise_error(YangJSON::ValidationError)
    expect { grove("small" => 128) }.to raise_error(YangJSON::ValidationError) { |e| expect(e.pointer).to eq("/orchard:grove/small") }
  end

  it "retains unknown extension values with warnings, but refuses to serialize them" do
    value = grove({ "vendor:future" => { "raw" => [1, true, "value"] } }, strict: false)
    expect(value["orchard:grove"]["vendor:future"]).to eq("raw" => [1, true, "value"])
    expect(value.warnings.first.rule).to eq("schema")
    expect { YangJSON.encode(value, schema) }.to raise_error(YangJSON::ValidationError)
  end

  it "offers parse and validate with typed diagnostics" do
    expect(YangJSON.parse("{}", schema: schema)).to eq({})
    expect(YangJSON.validate('{"orchard:grove":{"small":"x"}}', schema).first.pointer).to eq("/orchard:grove/small")
    expect(YangJSON.validate("[", schema).first.rule).to eq("parse")
    expect(YangJSON.validate("[]", schema).first.rule).to eq("structure")
    expect { YangJSON.decode("[]", schema, strict: false) }.to raise_error(YangJSON::ValidationError)
    expect(YangJson).to equal(YangJSON)
  end

  it "rejects duplicate and invalid normalized names" do
    expect(YangJSON.validate('{"orchard:grove":{"label":"a","orchard:label":"b"}}', schema).map(&:rule)).to include("duplicate")
    value = grove({ "bad~/name" => 2 }, strict: false)
    expect(value.warnings.first.pointer).to eq("/orchard:grove/bad~0~1name")
    expect(value["orchard:grove"]["bad~/name"]).to eq(2)
  end

  it "requires list keys, rejects duplicate key tuples, and preserves ordering" do
    data = grove("basket" => [{ "name" => "b", "number" => 2 }, { "number" => 1, "name" => "a" }])
    expect(JSON.parse(YangJSON.encode(data, schema))["orchard:grove"]["basket"].map { |entry| entry["name"] }).to eq(%w[b a])
    [{ "basket" => [{ "number" => 1 }] }, { "basket" => [{ "name" => "a" }, { "name" => "a" }] }].each do |bad|
      expect { grove(bad) }.to raise_error(YangJSON::ValidationError)
    end
  end

  [nil, 1, "x", []].each do |value|
    it("rejects nonobject containers #{value.inspect}") { expect { grove("basket" => [value]) }.to raise_error(YangJSON::ValidationError) }
  end
  %w[basket tags].each do |key|
    it("rejects nonarray #{key}") { expect { grove(key => {}) }.to raise_error(YangJSON::ValidationError) }
  end

  it "allows duplicate state leaf-list values since jtox lacks config" do
    expect(grove("tags" => %w[a a])["orchard:grove"]["orchard:tags"]).to eq(%w[a a])
  end

  it "does not mutate caller data or schema input" do
    source = '{"orchard:grove":{"label":"fresh"}}'
    result = YangJSON.decode(source, schema)
    encoded = YangJSON.encode(result, schema)
    result["orchard:grove"]["orchard:label"].replace("changed")
    expect(source).to eq(encoded)
    expect(schema).to be_frozen
  end

  it "preserves union wire member selection across integer/string ambiguities and edits" do
    [1, "1", "apple"].each do |value|
      data = grove("choice" => value)
      expect(JSON.parse(YangJSON.encode(data, schema))["orchard:grove"]["choice"]).to eq(value)
    end
    data = grove("choice" => "1")
    data["orchard:grove"]["orchard:choice"] = "changed"
    expect(JSON.parse(YangJSON.encode(data, schema))["orchard:grove"]["choice"]).to eq("changed")
  end

  it "round trips deterministic randomized records" do
    rng = Random.new(7951)
    150.times do |index|
      data = grove("count" => rng.rand(0...(2**64)).to_s, "small" => rng.rand(-128..127), "choice" => rng.rand(0..100),
                   "blob" => Base64.strict_encode64(rng.bytes(rng.rand(0..48))),
                   "price" => format("%<whole>d.%<fraction>02d", whole: rng.rand(1000), fraction: rng.rand(100)),
                   "tags" => Array.new(rng.rand(0..10)) { |n| "#{index}-#{n}" }, "basket" => [{ "name" => index.to_s }])
      expect(YangJSON.decode(YangJSON.encode(data, schema), schema)).to eq(data)
    end
  end
end
