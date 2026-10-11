# frozen_string_literal: true

require "spec_helper"
require_relative "../script/prepare_rfc_fixtures"

RSpec.describe "Downloaded RFC examples" do
  before(:all) { RFCFixtures.prepare }

  def reference(id)
    JSON.parse(File.read(File.join(RFCFixtures::DIRECTORY, "#{id}.json")))
  end

  def reference_schema(tree, annotations: {})
    modules = %w[example-foomod example-barmod example-mod iana-if-type ietf-interfaces ietf-ip ex-vlan example-last-modified foo bibliomod]
    YangJSON::Schema.new({ "modules" => modules.to_h { |name| [name, [name, "urn:test:#{name}"]] },
                           "tree" => tree, "annotations" => annotations })
  end

  def check_fragment(id, nodes, valid: true, annotations: {})
    value = reference(id)
    model = reference_schema({ "example-foomod:root" => ["container", nodes] }, annotations: annotations)
    source = JSON.generate("example-foomod:root" => value)
    if valid
      decoded = YangJSON.decode(source, model)
      expect(JSON.parse(YangJSON.encode(decoded, model))["example-foomod:root"]).to eq(value)
    else
      expect { YangJSON.decode(source, model) }.to raise_error(YangJSON::ValidationError)
    end
  end

  it "round trips both namespace and augment examples" do
    model = reference_schema({ "example-foomod:top" => ["container", { "foo" => %w[leaf uint8], "example-barmod:bar" => %w[leaf boolean] }] })
    %w[rfc7951_4_1 rfc7951_4_2].each do |id|
      source = JSON.generate(reference(id))
      expect(JSON.parse(YangJSON.encode(YangJSON.decode(source, model), model))).to eq(reference(id))
    end
  end

  it "checks every node-category example" do
    check_fragment("rfc7951_5.1_1", { "foo" => %w[leaf uint8] })
    check_fragment("rfc7951_5.2_1", { "bar" => ["container", { "foo" => %w[leaf uint8] }] })
    check_fragment("rfc7951_5.3_1", { "foo" => %w[leaf-list uint8] })
    check_fragment("rfc7951_5.4_1", { "bar" => ["list", { "foo" => %w[leaf uint8], "baz" => %w[leaf string] }, [%w[example-foomod foo]]] })
    check_fragment("rfc7951_5.5_1", { "data" => ["anydata"] })
    check_fragment("rfc7951_5.6_1", { "bar" => ["anyxml"] })
  end

  it "checks numeric, identityref, empty, union and instance-identifier examples" do
    check_fragment("rfc7951_6.1_1", { "foo" => %w[leaf uint64] })
    check_fragment("rfc7951_6.8_1", { "type" => %w[leaf identityref] })
    check_fragment("rfc7951_6.9_1", { "foo" => %w[leaf empty] })
    check_fragment("rfc7951_6.10_1", { "bar" => ["leaf", ["union", %w[uint16 string]]] }, valid: false)
    check_fragment("rfc7951_6.10_2", { "bar" => ["leaf", ["union", %w[uint16 string]]] })
    model = reference_schema({ "example-foomod:ref" => %w[leaf instance-identifier] })
    source = JSON.generate("example-foomod:ref" => reference("rfc7951_6.11_1"))
    expect(JSON.parse(YangJSON.encode(YangJSON.decode(source, model), model))["example-foomod:ref"]).to eq(reference("rfc7951_6.11_1"))
  end

  it "checks all five metadata examples including omitted trailing leaf-list annotations" do
    annotation = { "example-last-modified:last-modified" => "string" }
    check_fragment("rfc7952_5.2.2_1", { "cask" => ["container", {}] }, annotations: annotation)
    check_fragment("rfc7952_5.2.2_1", { "cask" => ["anydata"] }, annotations: annotation)
    check_fragment("rfc7952_5.2.2_2", { "seq" => ["list", { "name" => %w[leaf string] }, [%w[example-foomod name]]] }, annotations: annotation)
    check_fragment("rfc7952_5.2.3_1", { "foo:flag" => %w[leaf boolean] }, annotations: annotation)
    check_fragment("rfc7952_5.2.3_2", { "stuff" => ["anyxml"] }, annotations: annotation)
    check_fragment("rfc7952_5.2.4_1", { "bibliomod:folio" => %w[leaf-list uint8] }, annotations: annotation)
  end

  it "checks the complete appendix using a locally declared schema" do
    common = { "name" => %w[leaf string], "type" => %w[leaf identityref] }
    configuration = common.merge("enabled" => %w[leaf boolean], "ex-vlan:vlan-tagging" => %w[leaf boolean],
                                 "ex-vlan:base-interface" => %w[leaf string], "ex-vlan:vlan-id" => %w[leaf uint16])
    state = common.merge("admin-status" => %w[leaf enumeration], "oper-status" => %w[leaf enumeration],
                         "if-index" => %w[leaf int32], "phys-address" => %w[leaf string],
                         "higher-layer-if" => %w[leaf-list string], "lower-layer-if" => %w[leaf-list string],
                         "statistics" => ["container", { "discontinuity-time" => %w[leaf string] }])
    model = reference_schema({
      "ietf-interfaces:interfaces" => ["container", { "interface" => ["list", configuration, [%w[ietf-interfaces name]]] }],
      "ietf-interfaces:interfaces-state" => ["container", { "interface" => ["list", state, [%w[ietf-interfaces name]]] }]
    })
    source = reference("rfc7951_A_1")
    decoded = YangJSON.decode(JSON.generate(source), model)
    expect(JSON.parse(YangJSON.encode(decoded, model))).to eq(source)
    invalid = Marshal.load(Marshal.dump(source))
    invalid.fetch("ietf-interfaces:interfaces").fetch("interface")[2]["ex-vlan:vlan-id"] = 65_536
    expect { YangJSON.decode(JSON.generate(invalid), model) }.to raise_error(YangJSON::ValidationError)
  end
end
