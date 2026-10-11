# frozen_string_literal: true

require "spec_helper"

RSpec.describe YangJSON::Schema do
  it "loads a caller-authored schema without a schema compiler" do
    source = JSON.generate("modules" => { "garden" => ["g", "urn:example:garden"] },
                           "tree" => { "garden:harvest" => ["leaf", "uint64"] }, "annotations" => {})
    model = described_class.from_json(source)
    record = YangJSON.decode('{"garden:harvest":"9223372036854775808"}', model)
    expect(record.fetch("garden:harvest")).to eq(2**63)
    expect(YangJSON.encode(record, model)).to eq('{"garden:harvest":"9223372036854775808"}')
    expect(described_class.from_jtox(source).lookup("/garden:harvest").type).to eq("uint64")
  end

  it "applies input limits and rejects malformed schemas through the JSON entry point" do
    expect { described_class.from_json("{}") }.to raise_error(YangJSON::ParseError)
    expect { described_class.from_json("{}", max_bytes: 1) }.to raise_error(YangJSON::ParseError)
    expect { described_class.from_json("{}", max_depth: 0) }.to raise_error(ArgumentError)
  end
end
