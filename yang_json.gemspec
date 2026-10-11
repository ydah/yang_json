# frozen_string_literal: true

require_relative "lib/yang_json/version"

Gem::Specification.new do |spec|
  spec.name = "yang_json"
  spec.version = YangJSON::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]
  spec.summary = "Read and write RFC 7951 YANG JSON using caller-defined schemas"
  spec.description = "Schema-aware YANG JSON value conversion, namespace normalization, structural validation, and RFC 7952 annotations."
  spec.homepage = "https://github.com/ydah/yang_json"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "data/*.yml", "README.md", "CHANGELOG.md", "LICENSE.txt", "SECURITY.md"]
  spec.require_paths = ["lib"]
  spec.add_dependency "base64", ">= 0.2", "< 1"
  spec.add_dependency "bigdecimal", ">= 3.1", "< 5"
  spec.add_dependency "json", ">= 2.19.4", "< 4"
end
