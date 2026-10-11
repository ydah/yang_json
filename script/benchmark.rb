# frozen_string_literal: true

require_relative "../lib/yang_json"
require "objspace" if RUBY_ENGINE == "ruby"
elapsed = lambda do |&block|
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  block.call
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
end
schema = YangJSON::Schema.from_jtox(File.read(File.expand_path("../spec/fixtures/orchard.json", __dir__)))
count = Integer(ENV.fetch("RECORDS", "10000"))
source = JSON.generate("orchard:grove" => { "basket" => Array.new(count) { |i| { "name" => "record-#{i}", "number" => i % 65_536 } } })
GC.start
objects = GC.stat(:total_allocated_objects)
heap_before = ObjectSpace.memsize_of_all if ObjectSpace.respond_to?(:memsize_of_all)
document = nil
decode_time = elapsed.call { document = YangJSON.decode(source, schema) }
encode_time = elapsed.call { YangJSON.encode(document, schema) }
puts "#{count} list entries, #{source.bytesize} bytes: decode=#{decode_time.round(4)}s encode=#{encode_time.round(4)}s"
puts "Allocated objects=#{GC.stat(:total_allocated_objects) - objects}"
puts "Ruby heap growth=#{ObjectSpace.memsize_of_all - heap_before} bytes (not process peak RSS)" if heap_before
limit_time = elapsed.call do
  YangJSON.decode(source, schema, max_items: count - 1)
  raise "Expected item budget rejection"
rescue YangJSON::ParseError
  nil
end
puts "Limit rejection=#{limit_time.round(4)}s"
