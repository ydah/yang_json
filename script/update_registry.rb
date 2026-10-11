# frozen_string_literal: true

require "fileutils"
require "rexml/document"
require "digest"

path = File.expand_path("../tmp/registry/yang-parameters.xml", __dir__)
FileUtils.mkdir_p(File.dirname(path))
url = "https://www.iana.org/assignments/yang-parameters/yang-parameters.xml"
raise "IANA download failed" unless system("curl", "--fail", "--silent", "--show-error", "--location", "--proto", "=https", "--proto-redir", "=https",
                                           "--connect-timeout", "10", "--max-time", "60", url, "--output", path)

xml = REXML::Document.new(File.read(path))
raise "Unexpected registry" unless xml.root.attributes["id"] == "yang-parameters"

puts "IANA YANG Parameters: #{xml.root.elements["updated"]&.text}; SHA-256 #{Digest::SHA256.file(path).hexdigest} (ignored tmp/)"
puts "Module and annotation definitions are supplied by the caller's schema; no built-in registry to regenerate."
