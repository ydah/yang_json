# frozen_string_literal: true

require "spec_helper"

RSpec.describe "YANG primitive types" do
  %w[int8 int16 int32 int64 uint8 uint16 uint32 uint64].each do |type|
    width = type.delete_prefix("u").delete_prefix("int").to_i
    low = type.start_with?("u") ? 0 : -(2**(width - 1))
    high = type.start_with?("u") ? (2**width) - 1 : (2**(width - 1)) - 1
    it "round trips #{type} bounds" do
      [low, 0, high].each do |number|
        wire = width == 64 ? number.to_s : number
        expect(decode_value(wire, type)).to eq(number)
        expect(encode_value(number, type)).to eq(wire)
      end
    end
    it "rejects #{type} overflow, underflow and wrong JSON type" do
      [low - 1, high + 1, true, nil, [], {}, 1.1, (width == 64 ? 1 : "1")].each do |value|
        value = value.to_s if width == 64 && value.is_a?(Integer) && value != 1
        expect { decode_value(value, type) }.to raise_error(YangJSON::ValidationError)
      end
      expect { encode_value("1", type) }.to raise_error(YangJSON::ValidationError)
    end
  end

  it "checks int64 decimal lexical form and bounds before large conversions" do
    %w[0x10 1.0 1e2 NaN].push("1" * 129).each { |value| expect { decode_value(value, "uint64") }.to raise_error(YangJSON::ValidationError) }
    expect(decode_value("+001", "int64")).to eq(1)
  end

  it "uses exact BigDecimal and validates scaled signed 64-bit bounds" do
    [1, 2, 18].each do |digits|
      type = ["decimal64", digits]
      [-(2**63), 0, (2**63) - 1].each do |scaled|
        number = BigDecimal(scaled) / (10**digits)
        expect(decode_value(encode_value(number, type), type)).to eq(number)
      end
      expect { decode_value((BigDecimal(2**63) / (10**digits)).to_s("F"), type) }.to raise_error(YangJSON::ValidationError)
    end
    ["1.001", "1e1", ".2", "-", 1.25, "1" * 129].each { |value| expect { decode_value(value, ["decimal64", 2]) }.to raise_error(YangJSON::ValidationError) }
    expect(encode_value(BigDecimal("-0.0"), ["decimal64", 2])).to eq("0.0")
    expect { encode_value(1.25, ["decimal64", 2]) }.to raise_error(YangJSON::ValidationError)
  end

  %w[string enumeration].each do |type|
    it("preserves Unicode #{type}") { expect(decode_value("洋梨 🟢", type)).to eq("洋梨 🟢") }
    it("requires string #{type}") { expect { decode_value(1, type) }.to raise_error(YangJSON::ValidationError) }
  end

  it "checks boolean and empty distinctly" do
    [true, false].each { |value| expect(encode_value(decode_value(value, "boolean"), "boolean")).to eq(value) }
    expect(decode_value([nil], "empty")).to be(true)
    expect(encode_value(true, "empty")).to eq([nil])
    [nil, false, true, [], [nil, nil], 0].each { |value| expect { decode_value(value, "empty") }.to raise_error(YangJSON::ValidationError) }
    expect { decode_value(1, "boolean") }.to raise_error(YangJSON::ValidationError)
    expect { encode_value(false, "empty") }.to raise_error(YangJSON::ValidationError)
  end

  it "converts bits while rejecting duplicate or invalid names" do
    expect(decode_value("  a\t b\n", "bits")).to eq(%w[a b])
    expect(encode_value(%w[a b], "bits")).to eq("a b")
    expect(decode_value("", "bits")).to eq([])
    ["a a", "a:b", "9bad", nil].each { |value| expect { decode_value(value, "bits") }.to raise_error(YangJSON::ValidationError) }
    ["a", [nil], %w[a a]].each { |value| expect { encode_value(value, "bits") }.to raise_error(YangJSON::ValidationError) }
  end

  it "checks base64 padding, alphabet, pad bits, native encoding, and byte limits" do
    expect(decode_value("AP8=", "binary").encoding).to eq(Encoding::ASCII_8BIT)
    expect(encode_value("\x00\xff".b, "binary")).to eq("AP8=")
    [nil, "AB==", "AA", "AA==\n", "____", "=AAA"].each { |value| expect { decode_value(value, "binary") }.to raise_error(YangJSON::ValidationError) }
    expect { encode_value("hello", "binary") }.to raise_error(YangJSON::ValidationError)
    expect { decode_value("AAAA", "binary", max_binary_bytes: 1) }.to raise_error(YangJSON::ValidationError)
    expect { decode_value("AAAAAAAA", "binary", max_binary_bytes: 1) }.to raise_error(YangJSON::ValidationError)
    expect { encode_value("ab".b, "binary", max_binary_bytes: 1) }.to raise_error(YangJSON::ValidationError)
  end

  it "qualifies identities relative to their defining leaf module" do
    expect(decode_value("fruit", "identityref")).to eq("orchard:fruit")
    expect(decode_value("other:fruit", "identityref")).to eq("other:fruit")
    expect(encode_value("orchard:fruit", "identityref")).to eq("fruit")
    expect(encode_value("other:fruit", "identityref")).to eq("other:fruit")
    ["missing:fruit", "a:b:c", nil].each { |value| expect { decode_value(value, "identityref") }.to raise_error(YangJSON::ValidationError) }
    expect { encode_value("fruit", "identityref") }.to raise_error(YangJSON::ValidationError)
  end

  it "validates instance-identifier grammar and minimal namespace changes" do
    ["/orchard:grove/basket[name='a']/number", "/orchard:x/other:y[other-key=\"a/b\"]", "/orchard:x[2]",
     "/orchard:x[.='v']",
     "/orchard:x[other:key='v']", "/orchard:x[name=\"it's\"]", "/orchard:x[ key = 'v' ]", "/orchard:x[ 2 ]"].each do |value|
      expect(decode_value(value, "instance-identifier")).to eq(value)
    end
    ["", "/", "relative", "/x", "/unknown:x", "/orchard:x/orchard:y", "/orchard:x/", "/orchard:x[0]", "/orchard:x[01]",
     "/orchard:x[name=x]", "/orchard:x[orchard:key='x']", "/orchard:x[missing:key='x']", "/orchard:x garbage", "/orchard:x[2][3]",
     "/orchard:x[.='v'][k='v']", "/orchard:x[k='v'][2]"].each do |value|
      expect { decode_value(value, "instance-identifier") }.to raise_error(YangJSON::ValidationError)
    end
  end

  it "selects union branches using JSON token types, including nested unions" do
    type = ["union", %w[int16 string]]
    expect(decode_value(13, type)).to eq(13)
    expect(decode_value("13.5", type)).to eq("13.5")
    expect { decode_value(13.5, type) }.to raise_error(YangJSON::ValidationError)
    expect(decode_value(true, ["union", [type, "boolean"]])).to be(true)
    expect(encode_value(5, ["union", %w[uint64 uint32]])).to eq("5")
  end
end
