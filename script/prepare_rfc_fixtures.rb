# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tempfile"

module RFCFixtures
  ROOT = File.expand_path("../tmp/rfc", __dir__)
  DIRECTORY = File.join(ROOT, "fixtures")

  module_function

  def download(name, entry, directory)
    FileUtils.mkdir_p(directory)
    path = File.join(directory, name)
    unless File.file?(path)
      Tempfile.create("download", directory) do |file|
        success = system("curl", "--fail", "--silent", "--show-error", "--location", "--proto", "=https", "--proto-redir", "=https",
                         "--retry", "3", "--connect-timeout", "10", "--max-time", "60", entry.fetch("url"), "--output", file.path)
        raise "Reference download failed" unless success
        raise "Reference checksum mismatch" unless Digest::SHA256.file(file.path).hexdigest == entry.fetch("sha256")

        File.rename(file.path, path)
      end
    end
    raise "Reference checksum mismatch" unless Digest::SHA256.file(path).hexdigest == entry.fetch("sha256")

    path
  end

  def prepare
    FileUtils.mkdir_p(DIRECTORY)
    manifest = JSON.parse(File.read(File.join(__dir__, "rfc_sources.json")))
    entries = manifest.flat_map do |name, source|
      path = download(name, source, File.join(ROOT, "sources"))
      extract(File.read(path), name.delete_suffix(".txt"))
    end
    File.write(File.join(DIRECTORY, "manifest.json"), JSON.pretty_generate(entries))
    File.write(File.join(DIRECTORY, "LICENSE"), <<~NOTICE)
      RFC 7951 and RFC 7952 Code Components used only for conformance tests.
      Copyright (c) 2016 IETF Trust and the persons identified as authors of the code. All rights reserved.
      Redistribution and use in source and binary forms, with or without modification, is permitted pursuant to,
      and subject to the license terms contained in, the Revised BSD License set forth in Section 4.c of the
      IETF Trust's Legal Provisions Relating to IETF Documents (https://trustee.ietf.org/license-info).
      Source attribution and corrections: manifest.json and adjacent .original.txt files.
      The complete sources and author notices are in ../sources/.
    NOTICE
    raise "RFC fixture inventory changed" unless entries.length == 20

    puts "RFC fixtures: #{entries.length} JSON/instance-identifier examples (ignored tmp/)"
  end

  def extract(text, rfc)
    # Remove text-layout page boundaries, retaining the original blocks separately.
    text = text.gsub(/\n+Lhotka[^\n]*\n\f\nRFC [^\n]*\n+/, "\n")
    text = text.gsub(/\n(?=[A-Za-z0-9])/, "\n\n")
    section = nil
    counts = Hash.new(0)
    text.split(/\n[ \t]*\n/).filter_map do |block|
      heading = block.scan(/^([0-9]+(?:\.[0-9]+)*\.)  /).last
      section = heading.first.delete_suffix(".") if heading
      section = "A" if block.match?(/^Appendix A\./)
      original = block.strip
      next unless original.match?(%r{\A(?:\{|"[^"]+"\s*:|/ietf-interfaces:)})

      normalized = original.lines.reject { |line| line.strip == "..." }.join.gsub(/,\s*([}\]])/, '\1')
      normalization = []
      normalization << "removed omission markers and dangling commas" if normalized != original
      if normalized.start_with?("/")
        value = normalized
        normalization << "instance-identifier value is tested as a typed string"
      else
        unless normalized.start_with?("{")
          normalized = "{#{normalized}}"
          normalization << "wrapped member fragment in an object; tests supply the enclosing module"
        end
        value = JSON.parse(normalized)
      end
      counts[section] += 1
      id = "#{rfc}_#{section}_#{counts[section]}"
      File.write(File.join(DIRECTORY, "#{id}.original.txt"), original)
      File.write(File.join(DIRECTORY, "#{id}.json"), JSON.pretty_generate(value))
      { "id" => id, "rfc" => rfc, "section" => section, "normalization" => normalization }
    end
  end
end
RFCFixtures.prepare if $PROGRAM_NAME == __FILE__
