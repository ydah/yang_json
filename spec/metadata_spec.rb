# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RFC 7952 metadata and opaque nodes" do
  it "round trips typed annotations on every node category including leaf-list holes" do
    annotation = { "orchard-meta:revision" => "18446744073709551615", "orchard-meta:source" => "sensor" }
    wire = { "@" => annotation, "label" => "a", "@label" => annotation,
             "basket" => [{ "name" => "a", "@" => annotation }], "tags" => %w[a b c], "@tags" => [nil, annotation],
             "data" => { "@" => annotation, "value" => [nil] }, "xml" => [true, nil, true], "@xml" => annotation }
    result = grove(wire)
    expect(result["orchard:grove"]["@orchard:label"]["orchard-meta:revision"]).to eq((2**64) - 1)
    expect(JSON.parse(YangJSON.encode(result, schema))["orchard:grove"]).to eq(wire)
  end

  [
    { "@" => [] }, { "@" => { "source" => "sensor" } }, { "@" => { "unknown:source" => "sensor" } },
    { "@label" => {} }, { "label" => "x", "@orchard:label" => {} }, { "tags" => ["a"], "@tags" => [nil, {}] },
    { "tags" => "bad", "@tags" => [] }, { "tags" => ["a"], "@tags" => {} }, { "tags" => ["a"], "@tags" => [1] },
    { "basket" => [], "@basket" => {} }, { "data" => {}, "@data" => {} }, { "label" => "x", "@label" => [] },
    { "label" => "x", "@label" => { "orchard-meta:revision" => 1 } }
  ].each_with_index do |wire, index|
    it("rejects malformed metadata #{index}") { expect { grove(wire) }.to raise_error(YangJSON::ValidationError) }
  end

  it "rejects metadata for the top-level document" do
    expect { YangJSON.decode('{"@":{}}', schema) }.to raise_error(YangJSON::ValidationError)
  end

  it "keeps anyxml arbitrary JSON including empty arrays, null, and float precision" do
    wire = [true, nil, true, { "odd/key" => 1.2345678901234567 }]
    value = grove("xml" => wire)
    expect(JSON.parse(YangJSON.encode(value, schema))["orchard:grove"]["xml"]).to eq(wire)
  end

  it "retains anydata names and checks container-like JSON constraints" do
    wire = { "remote:event" => { "tags" => %w[a b], "empty" => [nil], "items" => [{ "name" => "x" }] } }
    value = grove("data" => wire)
    expect(value["orchard:grove"]["orchard:data"]).to eq(wire)
    expect(JSON.parse(YangJSON.encode(value, schema))["orchard:grove"]["data"]).to eq(wire)
  end

  [[], nil, 1, { "bad/name" => 1 }, { "leaf" => nil }, { "leaf" => [1, {}] }, { "leaf" => [1, 1] }, { "leaf" => [[1]] }].each_with_index do |wire, index|
    it("rejects invalid anydata #{index}") { expect { grove("data" => wire) }.to raise_error(YangJSON::ValidationError) }
  end

  it "rejects values outside the interoperable opaque JSON profile" do
    expect { grove("xml" => 2**53) }.to raise_error(YangJSON::ValidationError)
    [BigDecimal("1.2"), "\xff".b].each do |value|
      expect { YangJSON.encode({ "orchard:grove" => { "orchard:xml" => value } }, schema) }.to raise_error(YangJSON::ValidationError)
    end
  end
  it "handles metadata and empty scalar values within schema-less anydata" do
    annotation = { "orchard-meta:revision" => "7" }
    wire = { "nested" => { "@" => annotation, "leaf" => [nil], "@leaf" => annotation,
                           "items" => %w[a b], "@items" => [nil, annotation],
                           "empty-list" => [[nil]], "rows" => [{ "@" => annotation, "label" => "x" }] } }
    value = grove("data" => wire)
    expect(value["orchard:grove"]["orchard:data"]["nested"]["@"]["orchard-meta:revision"]).to eq(7)
    expect(JSON.parse(YangJSON.encode(value, schema))["orchard:grove"]["data"]).to eq(wire)
    [{ "@missing" => {} }, { "node" => {}, "@node" => {} }, { "items" => [1], "@items" => {} }].each do |invalid|
      expect { grove("data" => invalid) }.to raise_error(YangJSON::ValidationError)
    end
  end
end
